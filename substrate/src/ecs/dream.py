"""Offline Consolidation Engine ("Dream Phase" adapted from Khora)."""

from __future__ import annotations
from dataclasses import dataclass
from datetime import datetime, timezone
import json
import os
from pathlib import Path
from typing import Any

from .models import LifecycleState, EdgeType, MemoryEdge
from .db import ECSDatabase


@dataclass
class DreamAuditReport:
    total_atoms: int
    active_atoms: int
    stale_atoms: int
    superseded_atoms: int
    quarantined_atoms: int
    tombstones_past_retention: int
    aged_conflicts_eligible: int
    potential_contradictions: int
    dead_edges: int
    pending_candidates: int = 0
    pending_adjudications: int = 0
    provisional_atoms: int = 0
    low_efficacy_atoms: int = 0

    def to_dict(self) -> dict[str, Any]:
        return {
            "total_atoms": self.total_atoms,
            "active_atoms": self.active_atoms,
            "stale_atoms": self.stale_atoms,
            "superseded_atoms": self.superseded_atoms,
            "quarantined_atoms": self.quarantined_atoms,
            "tombstones_past_retention": self.tombstones_past_retention,
            "aged_conflicts_eligible": self.aged_conflicts_eligible,
            "potential_contradictions": self.potential_contradictions,
            "dead_edges": self.dead_edges,
            "pending_candidates": self.pending_candidates,
            "pending_adjudications": self.pending_adjudications,
            "provisional_atoms": self.provisional_atoms,
            "low_efficacy_atoms": self.low_efficacy_atoms,
        }


class DreamEngine:
    """Runs scheduled or on-demand offline consolidation with safety guardrails."""

    RETENTION_FLOOR_DAYS = 7
    MAX_CONFLICT_AGE_DAYS = 90

    def __init__(self, db: ECSDatabase, snapshot_dir: Path | str | None = None):
        self.db = db
        if snapshot_dir:
            self.snapshot_dir = Path(snapshot_dir)
            self.snapshot_dir.mkdir(parents=True, exist_ok=True)
        else:
            self.snapshot_dir = None

    def audit(self, project: str | None = None) -> DreamAuditReport:
        """Phase 1: Read-only audit of memory state & drift."""
        stats = self.db.get_stats(project=project)
        compaction = self.db.compact_tombstones(
            retention_days=self.RETENTION_FLOOR_DAYS,
            max_conflict_age_days=self.MAX_CONFLICT_AGE_DAYS,
            dry_run=True,
        )

        active_atoms = self.db.fetch_atoms(project=project, active_only=True)
        contradictions = 0
        for i in range(len(active_atoms)):
            for j in range(i + 1, len(active_atoms)):
                a, b = active_atoms[i], active_atoms[j]
                if a.file_path == b.file_path and a.symbol and a.symbol == b.symbol:
                    if a.resolution != b.resolution:
                        contradictions += 1

        # Check dead edges
        cur = self.db._conn.cursor()
        cur.execute("""
            SELECT COUNT(*) FROM memory_edges e
            LEFT JOIN memory_atoms a1 ON e.from_atom_id = a1.id
            LEFT JOIN memory_atoms a2 ON e.to_atom_id = a2.id
            WHERE a1.id IS NULL OR a2.id IS NULL
        """)
        dead_edges = cur.fetchone()[0]

        pending_candidates = len(self.db.fetch_atoms(project=project, state=LifecycleState.CANDIDATE, active_only=False))
        pending_adjudications = len(self.db.fetch_atoms(project=project, state=LifecycleState.PENDING_ADJUDICATION, active_only=False))
        
        cur.execute("SELECT COUNT(*) FROM memory_atoms WHERE state = 'active' AND trial_until IS NOT NULL")
        provisional_atoms = cur.fetchone()[0]

        cur.execute("SELECT COUNT(*) FROM memory_atoms WHERE state = 'active' AND failure_count > success_count AND confidence < 0.5")
        low_efficacy_atoms = cur.fetchone()[0]

        return DreamAuditReport(
            total_atoms=stats["total_atoms"],
            active_atoms=stats["active_atoms"],
            stale_atoms=stats["stale_atoms"],
            superseded_atoms=stats["superseded_atoms"],
            quarantined_atoms=stats["quarantined_atoms"],
            tombstones_past_retention=compaction["eligible"],
            aged_conflicts_eligible=compaction.get("archived_conflicts", 0),
            potential_contradictions=contradictions,
            dead_edges=dead_edges,
            pending_candidates=pending_candidates,
            pending_adjudications=pending_adjudications,
            provisional_atoms=provisional_atoms,
            low_efficacy_atoms=low_efficacy_atoms,
        )

    def apply(self, project: str | None = None) -> dict[str, Any]:
        """Phase 2: Executes consolidation plan with guardrails."""
        # Check kill-switch
        if os.environ.get("FLIGHTDECK_DREAM_DISABLE_APPLY") or os.environ.get("KHORA_DREAM_DISABLE_APPLY"):
            return {
                "status": "ABORTED",
                "reason": "FLIGHTDECK_DREAM_DISABLE_APPLY kill-switch active",
                "compacted": 0,
            }

        # 1. Snapshot-before-delete (save pre-state if directory configured)
        if self.snapshot_dir:
            cur = self.db._conn.cursor()
            cur.execute("SELECT * FROM memory_atoms WHERE state IN ('stale', 'superseded')")
            rows = [dict(r) for r in cur.fetchall()]
            ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
            undo_file = self.snapshot_dir / f"undo_dream_{ts}.json"
            undo_file.write_text(json.dumps(rows, indent=2))

        # 2. Compact tombstones and archive aged conflicts (>90 days)
        res = self.db.compact_tombstones(
            retention_days=self.RETENTION_FLOOR_DAYS,
            max_conflict_age_days=self.MAX_CONFLICT_AGE_DAYS,
            dry_run=False,
        )

        # 3. Resolve active contradictions by marking explicit CONTRADICTS edges
        active_atoms = self.db.fetch_atoms(project=project, active_only=True)
        flagged_conflicts = 0
        now = datetime.now(timezone.utc)

        for i in range(len(active_atoms)):
            for j in range(i + 1, len(active_atoms)):
                a, b = active_atoms[i], active_atoms[j]
                if a.file_path == b.file_path and a.symbol and a.symbol == b.symbol:
                    if a.resolution != b.resolution:
                        a.state = LifecycleState.CONFLICTED
                        b.state = LifecycleState.CONFLICTED
                        self.db.save_atom(a)
                        self.db.save_atom(b)
                        edge = MemoryEdge(
                            from_atom_id=a.id,
                            to_atom_id=b.id,
                            edge_type=EdgeType.CONTRADICTS,
                            valid_from=now,
                        )
                        self.db.save_edge(edge)
                        flagged_conflicts += 1

        # 4. Asynchronous Gate 3 Adjudication pass for background-mined candidates
        from .adjudication import AdjudicationEngine
        adjudicator = AdjudicationEngine(self.db)
        candidates = self.db.fetch_atoms(project=project, state=LifecycleState.CANDIDATE, active_only=False)
        reconciled_candidates = 0
        for cand in candidates:
            adjudicator.adjudicate_write(cand)
            reconciled_candidates += 1

        # 5. Clear expired trial_until on active provisional atoms (trial period completed safely)
        cur = self.db._conn.cursor()
        cur.execute(
            "SELECT id FROM memory_atoms WHERE state = 'active' AND trial_until IS NOT NULL AND trial_until <= ?",
            (now.isoformat(),),
        )
        expired_trial_ids = [r[0] for r in cur.fetchall()]
        for atom_id in expired_trial_ids:
            atom = self.db.get_atom(atom_id)
            if atom and atom.state == LifecycleState.ACTIVE:
                atom.trial_until = None
                self.db.save_atom(atom)

        # 6. Demote low-efficacy atoms to pending adjudication
        cur.execute(
            "SELECT id FROM memory_atoms WHERE state = 'active' AND failure_count > success_count AND confidence < 0.5"
        )
        toxic_ids = [r[0] for r in cur.fetchall()]
        for atom_id in toxic_ids:
            atom = self.db.get_atom(atom_id)
            if atom and atom.state == LifecycleState.ACTIVE:
                atom.state = LifecycleState.PENDING_ADJUDICATION
                msg = f"Quarantined by Dream Phase: low efficacy rating ({atom.failure_count} failures vs {atom.success_count} successes)"
                atom.conflict_note = f"{atom.conflict_note}; {msg}" if atom.conflict_note else msg
                self.db.save_atom(atom)

        return {
            "status": "APPLIED",
            "compacted_tombstones": res["deleted"],
            "flagged_conflicts": flagged_conflicts,
            "reconciled_candidates": reconciled_candidates,
            "promoted_provisional": len(expired_trial_ids),
            "demoted_low_efficacy": len(toxic_ids),
        }
