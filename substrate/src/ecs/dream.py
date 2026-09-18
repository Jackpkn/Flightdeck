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

        return {
            "status": "APPLIED",
            "compacted_tombstones": res["deleted"],
            "flagged_conflicts": flagged_conflicts,
            "reconciled_candidates": reconciled_candidates,
        }
