"""Budget-Aware Retrieval with FTS5 Lexical Search & On-Demand Anchor Verification."""

from __future__ import annotations
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .models import MemoryAtom, AnchorStatus, LifecycleState
from .db import ECSDatabase
from .git_probe import GitProbe, DriftReport


@dataclass
class RetrievalItem:
    atom: MemoryAtom
    relevance: float
    tokens: int
    content: str


@dataclass
class RetrievalResponse:
    status: str  # KNOWN, ADJACENT, UNKNOWN, DEGRADED
    results: list[RetrievalItem]
    blast_radius: list[str]
    has_more: bool
    total_tokens: int
    pending_adjudications_count: int = 0
    blast_radius_truncated: bool = False
    blast_radius_total_estimate: int = 0
    drift: dict[str, Any] | None = None
    query_tokens: int = 0
    top_bm25: float = 0.0
    results_count: int = 0
    hit_atom_ids: list[str] = field(default_factory=list)
    has_conflict: bool = False
    has_stale: bool = False
    latency_ms: float = 0.0

    def to_dict(self) -> dict[str, Any]:
        return {
            "status": self.status,
            "pending_adjudications_count": self.pending_adjudications_count,
            "results": [
                {
                    "id": item.atom.id,
                    "content": item.content,
                    "confidence": item.atom.confidence,
                    "authority": item.atom.authority.value,
                    "anchor_status": item.atom.anchor_status.value,
                    "relevance": round(item.relevance, 3),
                    "tokens": item.tokens,
                }
                for item in self.results
            ],
            "blast_radius": self.blast_radius,
            "blast_radius_truncated": self.blast_radius_truncated,
            "blast_radius_total_estimate": self.blast_radius_total_estimate,
            "has_more": self.has_more,
            "total_tokens": self.total_tokens,
            "drift": self.drift,
            "telemetry": {
                "query_tokens": self.query_tokens,
                "status": self.status,
                "top_bm25": round(self.top_bm25, 4),
                "results_count": self.results_count,
                "pending_adjudications_count": self.pending_adjudications_count,
                "hit_atom_ids": self.hit_atom_ids,
                "has_conflict": self.has_conflict,
                "has_stale": self.has_stale,
                "blast_truncated": self.blast_radius_truncated,
                "latency_ms": round(self.latency_ms, 2),
            },
        }

    @property
    def formatted_prompt_block(self) -> str:
        """Render ready-to-inject micro-directives block."""
        lines = []
        if self.pending_adjudications_count > 0:
            lines.extend([
                f"⚠️ [FLIGHTDECK ACTION REQUIRED: {self.pending_adjudications_count} pending memory adjudication(s)]",
                "> Unresolved candidate(s) need review. Call `memory_pending_adjudication` or run `ecs pending`.",
                "",
            ])
        if not self.results:
            return "\n".join(lines).strip()
        lines.extend([
            "### FLIGHTDECK CAUSAL MEMORY DIRECTIVES",
            "> Verified hazard traps and proven rules for current context:",
            "",
        ])
        for item in self.results:
            lines.append(item.content)
            lines.append("")
        return "\n".join(lines).strip()


class BudgetAwareRetriever:
    """Retrieves, on-demand verifies, and packs memories within a strict token budget."""

    def __init__(self, db: ECSDatabase, repo_root: Path | str | None = None):
        self.db = db
        self.repo_root = Path(repo_root or ".").resolve()

    def query(
        self,
        project: str,
        file_paths: list[str] | None = None,
        intent: str | None = None,
        budget_tokens: int = 500,
        max_results: int = 5,
        min_confidence: float = 0.5,
        graph_depth: int = 2,
    ) -> RetrievalResponse:
        """
        Budget-aware retrieval with FTS5 lexical matching and on-demand anchor verification.
        Blocks 'contradicted' memories and applies staleness warnings.
        """
        t_start = time.perf_counter()
        clean_paths = [p.strip().lstrip("./") for p in (file_paths or [])]
        query_text = intent or " ".join(Path(p).stem for p in clean_paths)
        query_token_count = len(query_text.split())
        pending_count = self.db.fetch_pending_adjudication_count(project=project)

        # 1. FTS5 Search with File Overlap & Staleness Penalty
        fts_results = self.db.search_fts(
            query_text=query_text,
            project=project,
            active_files=clean_paths,
            limit=30,
        )

        # If FTS returns few or no results, fallback to path-based fetch
        if not fts_results and clean_paths:
            fallback_atoms = []
            for path in clean_paths:
                fallback_atoms.extend(self.db.fetch_atoms(
                    project=project,
                    file_path=path,
                    active_only=True,
                    min_confidence=min_confidence,
                ))
            fts_results = [(atom, 0.85 * atom.authority.trust_score) for atom in fallback_atoms]

        if not fts_results:
            latency_ms = (time.perf_counter() - t_start) * 1000
            return RetrievalResponse(
                status="UNKNOWN",
                results=[],
                blast_radius=[],
                has_more=False,
                total_tokens=0,
                pending_adjudications_count=pending_count,
                query_tokens=query_token_count,
                top_bm25=0.0,
                results_count=0,
                latency_ms=latency_ms,
            )

        # 2. On-Demand Anchor Verification (Context Fabric pattern)
        verified_candidates: list[tuple[MemoryAtom, float]] = []
        all_for_drift: list[MemoryAtom] = []

        for atom, score in fts_results:
            all_for_drift.append(atom)
            # Re-check anchor against committed blob
            verified_atom = GitProbe.verify_atom_on_demand(atom, self.repo_root)

            # Block contradicted atoms from fact injection
            if verified_atom.anchor_status == AnchorStatus.CONTRADICTED:
                continue
            if verified_atom.anchor_status == AnchorStatus.MISSING_SOURCE:
                continue

            # Persist updated status only if changed
            if verified_atom.anchor_status != atom.anchor_status:
                self.db.save_atom(verified_atom)
            verified_candidates.append((verified_atom, score))

        # Compute drift report for candidate set
        drift_rep = GitProbe.compute_drift_report(all_for_drift, self.repo_root)

        # Filter candidates by minimum relevance threshold (0.35) to reject spurious single-token noise on null queries
        verified_candidates = [c for c in verified_candidates if c[1] >= 0.35]

        if not verified_candidates:
            latency_ms = (time.perf_counter() - t_start) * 1000
            return RetrievalResponse(
                status="UNKNOWN",
                results=[],
                blast_radius=[],
                has_more=False,
                total_tokens=0,
                pending_adjudications_count=pending_count,
                query_tokens=query_token_count,
                top_bm25=0.0,
                results_count=0,
                latency_ms=latency_ms,
                drift={
                    "severity": drift_rep.severity,
                    "drift_fraction": drift_rep.drift_fraction,
                    "verified": drift_rep.verified_count,
                    "stale": drift_rep.stale_count,
                    "contradicted": drift_rep.contradicted_count,
                },
            )

        # Sort by relevance descending, then confidence
        verified_candidates.sort(key=lambda x: (x[1], x[0].confidence), reverse=True)

        top_score = verified_candidates[0][1]
        # Status confidence floor: require >= 0.55 for KNOWN; >= 0.30 for ADJACENT; below is UNKNOWN
        if top_score >= 0.55:
            status = "KNOWN"
        elif top_score >= 0.30:
            status = "ADJACENT"
        else:
            status = "UNKNOWN"

        # 3. Pack under budget
        packed_items: list[RetrievalItem] = []
        total_tokens = 0
        all_blast_radius: set[str] = set()
        blast_radius_truncated = False
        blast_radius_total_estimate = 0
        has_more = False

        for atom, score in verified_candidates:
            directive = atom.micro_directive
            tokens = atom.token_estimate

            if len(packed_items) >= max_results or (total_tokens + tokens) > budget_tokens:
                has_more = True
                break

            packed_items.append(RetrievalItem(
                atom=atom,
                relevance=score,
                tokens=tokens,
                content=directive,
            ))
            total_tokens += tokens
            self.db.record_hit(atom.id)

            # Recursive CTE blast radius with truncation metrics
            blast = self.db.compute_blast_radius(atom.id, max_depth=graph_depth)
            all_blast_radius.update(blast.nodes)
            if blast.truncated:
                blast_radius_truncated = True
            blast_radius_total_estimate += blast.total_estimate

        has_conflict = any(item.atom.state == LifecycleState.CONFLICTED for item in packed_items)
        has_stale = any(item.atom.anchor_status == AnchorStatus.STALE or item.atom.state == LifecycleState.STALE for item in packed_items)
        hit_ids = [item.atom.id for item in packed_items]
        latency_ms = (time.perf_counter() - t_start) * 1000

        return RetrievalResponse(
            status=status,
            results=packed_items,
            blast_radius=sorted(all_blast_radius),
            has_more=has_more,
            total_tokens=total_tokens,
            pending_adjudications_count=pending_count,
            blast_radius_truncated=blast_radius_truncated,
            blast_radius_total_estimate=blast_radius_total_estimate,
            query_tokens=query_token_count,
            top_bm25=top_score,
            results_count=len(packed_items),
            hit_atom_ids=hit_ids,
            has_conflict=has_conflict,
            has_stale=has_stale,
            latency_ms=latency_ms,
            drift={
                "severity": drift_rep.severity,
                "drift_fraction": drift_rep.drift_fraction,
                "verified": drift_rep.verified_count,
                "stale": drift_rep.stale_count,
                "contradicted": drift_rep.contradicted_count,
            },
        )
