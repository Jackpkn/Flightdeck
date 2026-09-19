"""Stateless MCP Server for Flightdeck Epistemic Causal Substrate (ECS)."""

from __future__ import annotations
import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from mcp.server.mcpserver import MCPServer

from .models import (
    AuthorityLevel,
    MemoryKind,
    LifecycleState,
    MemoryAtom,
)
from .db import ECSDatabase
from .adjudication import AdjudicationEngine
from .retrieval import BudgetAwareRetriever
from .dream import DreamEngine


def log_telemetry_event(event_data: dict[str, Any]) -> None:
    """Appends structured telemetry event to Flightdeck JSONL log for empirical calibration."""
    try:
        log_path_str = os.environ.get("FLIGHTDECK_TELEMETRY_LOG")
        if log_path_str:
            log_path = Path(log_path_str).expanduser()
        else:
            app_support = Path("~/Library/Application Support/Flightdeck").expanduser()
            app_support.mkdir(parents=True, exist_ok=True)
            log_path = app_support / "ecs_telemetry.jsonl"
        log_path.parent.mkdir(parents=True, exist_ok=True)
        event_data["timestamp"] = datetime.now(timezone.utc).isoformat()
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(event_data) + "\n")
    except Exception:
        pass


def get_default_db_path() -> Path:
    env_path = os.environ.get("FLIGHTDECK_ECS_DB")
    if env_path:
        return Path(env_path).expanduser()
    app_support = Path("~/Library/Application Support/Flightdeck").expanduser()
    app_support.mkdir(parents=True, exist_ok=True)
    return app_support / "ecs.sqlite"


def create_mcp_server(db_path: str | Path | None = None) -> MCPServer:
    """Instantiates stateless MCP server for ECS."""
    db = ECSDatabase(db_path or get_default_db_path())
    adjudicator = AdjudicationEngine(db)
    retriever = BudgetAwareRetriever(db)
    dreamer = DreamEngine(db)

    server = MCPServer("flightdeck-ecs", version="0.1.0")

    @server.tool()
    def memory_context(
        project: str,
        file_paths: list[str] = [],
        intent: str = "",
        budget_tokens: int = 500,
        min_confidence: float = 0.6,
        graph_depth: int = 2,
    ) -> str:
        """
        Retrieves task-scoped causal memory directives within a strict token budget.
        Returns both formatted micro-directives, JSON metadata, and telemetry diagnostics.
        """
        resp = retriever.query(
            project=project,
            file_paths=file_paths,
            intent=intent,
            budget_tokens=budget_tokens,
            min_confidence=min_confidence,
            graph_depth=graph_depth,
        )

        telemetry_event = {
            "event": "memory_context",
            "project": project,
            "query_tokens": resp.query_tokens,
            "status": resp.status,
            "top_bm25": round(resp.top_bm25, 4),
            "results_count": resp.results_count,
            "hit_atom_ids": resp.hit_atom_ids,
            "has_conflict": resp.has_conflict,
            "has_stale": resp.has_stale,
            "blast_truncated": resp.blast_radius_truncated,
            "latency_ms": round(resp.latency_ms, 2),
        }
        log_telemetry_event(telemetry_event)

        output: dict[str, Any] = {
            "status": resp.status,
            "prompt_block": resp.formatted_prompt_block,
            "blast_radius": resp.blast_radius,
            "blast_radius_truncated": resp.blast_radius_truncated,
            "blast_radius_total_estimate": resp.blast_radius_total_estimate,
            "total_tokens": resp.total_tokens,
            "telemetry": telemetry_event,
            "results": [
                {
                    "id": item.atom.id,
                    "kind": item.atom.kind.value,
                    "directive": item.content,
                    "confidence": item.atom.confidence,
                    "authority": item.atom.authority.value,
                    "relevance": round(item.relevance, 3),
                }
                for item in resp.results
            ],
        }
        return json.dumps(output, indent=2)

    @server.tool()
    def memory_store(
        project: str,
        file_path: str,
        kind: str,
        trigger_pattern: str,
        resolution: str,
        authority: str = "L2",
        symbol: str = "",
        failure_signature: str = "",
        agent_id: str = "",
        session_id: str = "",
        verified_by: str = "",
        parent_id: str = "",
    ) -> str:
        """
        Stores a verified memory atom after running write-side adjudication (CUPMem protocol).
        Quarantines L4 external documents and handles superseding of older memories.
        Optionally links to parent_id (LEADS_TO_DEAD_END if kind == 'dead_end', DEPENDS_ON otherwise).
        """
        t_store_start = time.perf_counter()
        try:
            mem_kind = MemoryKind(kind.lower())
        except ValueError:
            mem_kind = MemoryKind.RULE

        try:
            auth = AuthorityLevel.from_str(authority)
        except ValueError:
            auth = AuthorityLevel.L2

        atom = MemoryAtom(
            project=project,
            file_path=file_path,
            kind=mem_kind,
            authority=auth,
            symbol=symbol if symbol else None,
            trigger_pattern=trigger_pattern,
            failure_signature=failure_signature if failure_signature else None,
            resolution=resolution,
            agent_id=agent_id if agent_id else None,
            session_id=session_id if session_id else None,
            verified_by=verified_by if verified_by else ("compiler" if auth == AuthorityLevel.L1 else "host_agent:claude_code"),
        )

        persisted, affected, edges = adjudicator.adjudicate_write(atom)

        # Link to parent if provided
        if parent_id and db.get_atom(parent_id):
            link_edge_type = EdgeType.LEADS_TO_DEAD_END if mem_kind == MemoryKind.DEAD_END else EdgeType.DEPENDS_ON
            edge = MemoryEdge(from_atom_id=parent_id, to_atom_id=persisted.id, edge_type=link_edge_type)
            db.save_edge(edge)
            edges.append(edge)

        store_latency_ms = (time.perf_counter() - t_store_start) * 1000

        superseded_ids = [a.id for a in affected if a.state == LifecycleState.SUPERSEDED]
        conflicted_ids = [a.id for a in affected if a.state == LifecycleState.CONFLICTED]

        if superseded_ids:
            adj_res = "REPLACE"
        elif conflicted_ids:
            adj_res = "CONFLICT"
        elif persisted.state == LifecycleState.STALE:
            adj_res = "STALE"
        elif persisted.state == LifecycleState.PENDING_ADJUDICATION:
            adj_res = "PENDING_ADJUDICATION"
        else:
            adj_res = "KEEP"

        log_telemetry_event({
            "event": "memory_store",
            "project": project,
            "atom_id": persisted.id,
            "authority_level": persisted.authority.value,
            "kind": persisted.kind.value,
            "adjudication_result": adj_res,
            "conflict_candidates": len(affected),
            "latency_ms": round(store_latency_ms, 2),
        })

        res = {
            "stored_atom_id": persisted.id,
            "state": persisted.state.value,
            "authority": persisted.authority.value,
            "verified_by": persisted.verified_by,
            "reward": persisted.reward,
            "confidence": persisted.confidence,
            "label": persisted.label,
            "adjudication_result": adj_res,
            "superseded_atoms": superseded_ids,
            "conflicted_atoms": conflicted_ids,
            "causal_edges_created": len(edges),
            "micro_directive": persisted.micro_directive,
        }
        return json.dumps(res, indent=2)

    @server.tool()
    def memory_record_dead_end(
        file_path: str,
        attempted_fix: str,
        failure_signature: str = "",
        trigger_pattern: str = "",
        symbol: str = "",
        parent_atom_id: str = "",
        project: str = "default",
    ) -> str:
        """
        Records a falsified hypothesis (dead end) to prevent coding agents from repeating failed approaches.
        Optionally links to a parent problem or trap atom via a LEADS_TO_DEAD_END causal edge.
        """
        dead_end_atom, edge = db.record_dead_end(
            parent_id=parent_atom_id if parent_atom_id else None,
            file_path=file_path,
            attempted_fix=attempted_fix,
            failure_signature=failure_signature,
            trigger_pattern=trigger_pattern,
            symbol=symbol if symbol else None,
            project=project,
        )
        return json.dumps({
            "status": "RECORDED",
            "atom_id": dead_end_atom.id,
            "kind": dead_end_atom.kind.value,
            "linked_parent_id": parent_atom_id if parent_atom_id else None,
            "edge_id": edge.id if edge else None,
            "edge_type": edge.edge_type.value if edge else None,
            "directive": dead_end_atom.micro_directive,
        }, indent=2)

    @server.tool()
    def memory_search(
        project: str,
        file_path: str = "",
        symbol: str = "",
        state: str = "active",
        min_confidence: float = 0.5,
    ) -> str:
        """Searches active or historical memory atoms."""
        st = None
        if state:
            try:
                st = LifecycleState(state.lower())
            except ValueError:
                pass

        atoms = db.fetch_atoms(
            project=project,
            file_path=file_path if file_path else None,
            symbol=symbol if symbol else None,
            state=st,
            min_confidence=min_confidence,
            active_only=(st is None),
        )

        return json.dumps([a.to_dict() for a in atoms], indent=2)

    @server.tool()
    def memory_adjudicate(
        candidate_id: str,
        decision: str,
        reason: str = "",
        host_agent: str = "claude_code",
        target_file: str = "",
    ) -> str:
        """
        Gate 4: Deferred AI Adjudication via Host Agent MCP.
        Allows the host agent (Claude, Cursor, Antigravity) to resolve pending items:
        - 'attribute': Disambiguates multi-file diff to specific cause
        - 'valid': Re-verifies content dependency after refactor
        - 'stale' / 'invalid': Confirms content dependency broken
        - 'distinct_scope': Disambiguates equal-authority claims to different contexts
        - 'resolve_conflict': Chooses winning claim between equal authorities
        """
        res = adjudicator.adjudicate_host_agent(
            candidate_id=candidate_id,
            host_agent=host_agent,
            decision=decision,
            reason=reason,
            target_file=target_file if target_file else None,
        )
        log_telemetry_event({
            "event": "memory_adjudicate",
            "candidate_id": candidate_id,
            "host_agent": host_agent,
            "decision": decision,
            "status": res.get("status"),
        })
        return json.dumps(res, indent=2)

    @server.tool()
    def memory_pending_adjudication(project: str = "") -> str:
        """
        Lists memory candidates sitting in 'pending_adjudication' or unresolved 'conflicted'
        state waiting for host-agent review (Gate 4).
        """
        pending_atoms = db.fetch_atoms(
            project=project if project else None,
            state=LifecycleState.PENDING_ADJUDICATION,
            active_only=False,
        )
        conflicted_atoms = db.fetch_atoms(
            project=project if project else None,
            state=LifecycleState.CONFLICTED,
            active_only=False,
        )

        items = []
        for a in pending_atoms + conflicted_atoms:
            items.append({
                "id": a.id,
                "project": a.project,
                "file_path": a.file_path,
                "state": a.state.value,
                "kind": a.kind.value,
                "authority": a.authority.value,
                "verified_by": a.verified_by,
                "trigger_pattern": a.trigger_pattern,
                "failure_signature": a.failure_signature,
                "resolution": a.resolution,
                "conflict_note": a.conflict_note,
                "evidence_refs": a.evidence_refs,
                "confidence": a.confidence,
                "updated_at": a.updated_at.isoformat(),
            })

        return json.dumps({
            "pending_count": len(items),
            "candidates": items,
        }, indent=2)

    @server.tool()
    def memory_resolve(atom_id: str, action: str) -> str:
        """
        Explicitly resolves a memory atom: 'stale' (retire), 'replace' (supersede), or 'active'.
        """
        atom = db.get_atom(atom_id)
        if not atom:
            return json.dumps({"error": f"Atom not found: {atom_id}"})

        act = action.lower()
        if act == "stale":
            db.invalidate_atom(atom_id)
            atom.state = LifecycleState.STALE
            db.save_atom(atom)
            return json.dumps({"status": "RESOLVED", "atom_id": atom_id, "state": "stale"})
        elif act == "active":
            atom.state = LifecycleState.ACTIVE
            atom.valid_until = None
            db.save_atom(atom)
            return json.dumps({"status": "RESOLVED", "atom_id": atom_id, "state": "active"})
        else:
            return json.dumps({"error": f"Unsupported action: {action}"})

    @server.tool()
    def memory_status(project: str = "") -> str:
        """Reports health, atom counts, edge counts, and database storage location."""
        stats = db.get_stats(project=project if project else None)
        return json.dumps(stats, indent=2)

    @server.tool()
    def memory_dream(project: str = "", apply: bool = False) -> str:
        """
        Runs the Khora-style Dream Phase offline consolidation.
        If apply=False (default), runs read-only audit. If apply=True, applies tombstone compaction.
        """
        if apply:
            res = dreamer.apply(project=project if project else None)
            return json.dumps(res, indent=2)
        else:
            audit = dreamer.audit(project=project if project else None)
            return json.dumps(audit.to_dict(), indent=2)

    @server.tool()
    def memory_export(project: str = "", output_dir: str = ".flightdeck/memory") -> str:
        """
        Exports active verified memory atoms and causal edges to .flightdeck/memory/ JSONL files.
        Enables team and CI synchronization via Git commits without cloud dependencies.
        """
        from .federation import export_memory
        atoms_cnt, edges_cnt = export_memory(db, output_dir=output_dir, project=project if project else None)
        return json.dumps({
            "status": "EXPORTED",
            "output_dir": output_dir,
            "atoms_count": atoms_cnt,
            "edges_count": edges_cnt,
        }, indent=2)

    @server.tool()
    def memory_import(project: str = "", input_dir: str = ".flightdeck/memory") -> str:
        """
        Imports memory atoms and causal edges from .flightdeck/memory/ JSONL files.
        Applies write-side adjudication (Gate 3) against existing local memories.
        """
        from .federation import import_memory
        res = import_memory(db, input_dir=input_dir, project=project if project else None)
        return json.dumps({
            "status": "IMPORTED",
            "input_dir": input_dir,
            **res,
        }, indent=2)

    @server.tool()
    def memory_sync(project: str = "", repo_root: str = ".") -> str:
        """
        Two-way synchronization between local SQLite database and Git repository .flightdeck/memory/ JSONL.
        Imports teammate memories and exports local verified atoms back.
        """
        from .federation import sync_memory
        res = sync_memory(db, repo_root=repo_root, project=project if project else None)
        return json.dumps({
            "status": "SYNCED",
            **res,
        }, indent=2)

    return server


if __name__ == "__main__":
    server = create_mcp_server()
    server.run(transport="stdio")

