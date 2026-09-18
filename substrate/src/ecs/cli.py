"""Command Line Interface for Flightdeck Epistemic Causal Substrate (ECS)."""

from __future__ import annotations
import argparse
import json
import sys
from pathlib import Path

from .models import (
    AuthorityLevel,
    MemoryKind,
    MemoryAtom,
)
from .db import ECSDatabase
from .adjudication import AdjudicationEngine
from .retrieval import BudgetAwareRetriever
from .dream import DreamEngine
from .server import create_mcp_server, get_default_db_path


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="ecs",
        description="⚡️ Flightdeck Epistemic Causal Substrate (ECS) Memory CLI",
    )
    parser.add_argument(
        "--db",
        type=str,
        default=None,
        help="Path to SQLite database file",
    )

    subparsers = parser.add_subparsers(dest="subcommand", required=True)

    # 1. check
    check_p = subparsers.add_parser("check", help="Check active hazard traps and rules for files")
    check_p.add_argument("files", nargs="+", help="File paths to query")
    check_p.add_argument("--project", default="Flightdeck", help="Project name")
    check_p.add_argument("--budget", type=int, default=500, help="Token budget")
    check_p.add_argument("--json", action="store_true", help="Output as JSON")

    # 2. store
    store_p = subparsers.add_parser("store", help="Store a verified memory atom")
    store_p.add_argument("--project", required=True, help="Project name")
    store_p.add_argument("--file", required=True, help="Target file path")
    store_p.add_argument("--kind", choices=["trap", "rule", "invariant", "lesson", "dead_end"], default="trap")
    store_p.add_argument("--authority", choices=["L0", "L1", "L2", "L2a", "L2b", "L3", "L4"], default="L2")
    store_p.add_argument("--trigger", required=True, help="Trigger pattern / mistake")
    store_p.add_argument("--resolution", required=True, help="Resolution / correct pattern")
    store_p.add_argument("--symbol", default="", help="Optional symbol name (path::symbol)")
    store_p.add_argument("--failure", default="", help="Optional compiler error / failure signature")

    # 3. list
    list_p = subparsers.add_parser("list", help="List active memory atoms")
    list_p.add_argument("--project", default=None, help="Filter by project")
    list_p.add_argument("--file", default=None, help="Filter by file path")
    list_p.add_argument("--all", action="store_true", help="Include stale/superseded atoms")

    # 4. pending
    pending_p = subparsers.add_parser("pending", help="List memory candidates awaiting Gate 4 adjudication")
    pending_p.add_argument("--project", default=None, help="Filter by project")
    pending_p.add_argument("--json", action="store_true", help="Output as JSON")

    # 5. adjudicate
    adj_p = subparsers.add_parser("adjudicate", help="Gate 4: Adjudicate a pending candidate")
    adj_p.add_argument("candidate_id", help="ID of candidate to adjudicate")
    adj_p.add_argument("decision", help="Adjudication decision (attribute, valid, stale, distinct_scope, resolve_conflict, validate_advice)")
    adj_p.add_argument("--reason", default="", help="Rationale for adjudication")
    adj_p.add_argument("--target-file", default=None, help="Target file for attribution")
    adj_p.add_argument("--host-agent", default="cli_operator", help="Adjudicating agent identifier")

    # 6. status
    status_p = subparsers.add_parser("status", help="Show substrate statistics and health")
    status_p.add_argument("--project", default=None, help="Optional project filter")

    # 7. dream
    dream_p = subparsers.add_parser("dream", help="Run Khora-style Dream Phase consolidation")
    dream_p.add_argument("--project", default=None, help="Optional project filter")
    dream_p.add_argument("--apply", action="store_true", help="Apply compaction (default is dry-run audit)")

    # 8. serve
    serve_p = subparsers.add_parser("serve", help="Run MCP stdio server for Claude Code / Cursor")

    args = parser.parse_args()
    db_path = args.db or get_default_db_path()

    if args.subcommand == "serve":
        server = create_mcp_server(db_path)
        server.run(transport="stdio")
        return

    db = ECSDatabase(db_path)

    if args.subcommand == "check":
        retriever = BudgetAwareRetriever(db)
        resp = retriever.query(
            project=args.project,
            file_paths=args.files,
            budget_tokens=args.budget,
        )
        if args.json:
            print(json.dumps(resp.to_dict(), indent=2))
        else:
            if resp.results:
                print(resp.formatted_prompt_block)
            else:
                print(f"✓ No active hazard traps or warnings for {', '.join(args.files)}")

    elif args.subcommand == "store":
        adjudicator = AdjudicationEngine(db)
        atom = MemoryAtom(
            project=args.project,
            file_path=args.file,
            kind=MemoryKind(args.kind),
            authority=AuthorityLevel.from_str(args.authority),
            trigger_pattern=args.trigger,
            resolution=args.resolution,
            symbol=args.symbol if args.symbol else None,
            failure_signature=args.failure if args.failure else None,
        )
        persisted, affected, edges = adjudicator.adjudicate_write(atom)
        print(f"✓ Stored {persisted.kind.badge} (ID: {persisted.id[:8]}...)")
        print(f"  State: {persisted.state.value.upper()} | Authority: {persisted.authority.value} | Confidence: {persisted.confidence:.2f}")
        if persisted.is_provisional:
            print(f"  ⚠️ Under provisional trial until: {persisted.trial_until.isoformat() if persisted.trial_until else 'N/A'}")
        if affected:
            print(f"  Superseded/Affected: {len(affected)} existing memory atom(s)")
        if edges:
            print(f"  Edges created: {len(edges)}")

    elif args.subcommand == "list":
        atoms = db.fetch_atoms(
            project=args.project,
            file_path=args.file,
            active_only=(not args.all),
        )
        if not atoms:
            print("No memory atoms found.")
            return

        print(f"--- FLIGHTDECK CAUSAL MEMORY ATOMS ({len(atoms)}) ---")
        for a in atoms:
            sym = f" :: {a.symbol}" if a.symbol else ""
            prov = " [PROVISIONAL TRIAL]" if a.is_provisional else ""
            print(f"[{a.kind.badge}] {a.file_path}{sym} ({a.state.value.upper()}){prov}")
            print(f"  Trigger: {a.trigger_pattern}")
            print(f"  Fix:     {a.resolution}")
            print(f"  Auth: {a.authority.value} | Conf: {a.confidence:.2f} | Hits: {a.hit_count}")
            print()

    elif args.subcommand == "pending":
        pending_atoms = db.fetch_atoms(
            project=args.project,
            state=LifecycleState.PENDING_ADJUDICATION,
            active_only=False,
        )
        conflicted_atoms = db.fetch_atoms(
            project=args.project,
            state=LifecycleState.CONFLICTED,
            active_only=False,
        )
        all_pending = pending_atoms + conflicted_atoms

        if args.json:
            print(json.dumps([a.to_dict() for a in all_pending], indent=2))
        else:
            if not all_pending:
                print("✓ No pending adjudications.")
                return
            print(f"--- PENDING ADJUDICATIONS ({len(all_pending)}) ---")
            for a in all_pending:
                print(f"[{a.id[:8]}] ({a.state.value.upper()}) {a.file_path}")
                print(f"  Trigger: {a.trigger_pattern}")
                print(f"  Fix:     {a.resolution}")
                print(f"  Auth:    {a.authority.value} | Verified By: {a.verified_by}")
                if a.conflict_note:
                    print(f"  Note:    {a.conflict_note}")
                print(f"  Action:  ecs adjudicate {a.id} <decision> --reason <reason>")
                print()

    elif args.subcommand == "adjudicate":
        adjudicator = AdjudicationEngine(db)
        res = adjudicator.adjudicate_host_agent(
            candidate_id=args.candidate_id,
            host_agent=args.host_agent,
            decision=args.decision,
            reason=args.reason,
            target_file=args.target_file,
        )
        print("✓ Adjudication processed:")
        print(json.dumps(res, indent=2))

    elif args.subcommand == "status":
        stats = db.get_stats(project=args.project)
        print("⚡️ FLIGHTDECK EPISTEMIC CAUSAL SUBSTRATE (ECS) STATUS")
        print(f"  Database:     {stats['database_path']}")
        print(f"  Total Atoms:  {stats['total_atoms']}")
        print(f"  Active:       {stats['active_atoms']}")
        print(f"  Stale:        {stats['stale_atoms']}")
        print(f"  Superseded:   {stats['superseded_atoms']}")
        print(f"  Quarantined:  {stats['quarantined_atoms']}")
        print(f"  Causal Edges: {stats['total_edges']}")

    elif args.subcommand == "dream":
        dreamer = DreamEngine(db)
        if args.apply:
            res = dreamer.apply(project=args.project)
            print("🌙 DREAM PHASE: CONSOLIDATION APPLIED")
            print(f"  Status:               {res['status']}")
            print(f"  Compacted Tombstones: {res['compacted_tombstones']}")
            print(f"  Flagged Conflicts:    {res['flagged_conflicts']}")
        else:
            audit = dreamer.audit(project=args.project)
            print("🌙 DREAM PHASE: READ-ONLY AUDIT")
            print(f"  Active Atoms:            {audit.active_atoms}")
            print(f"  Tombstones (Stale/Sup):  {audit.stale_atoms + audit.superseded_atoms}")
            print(f"  Past Retention Floor:    {audit.tombstones_past_retention}")
            print(f"  Contradiction Pairs:     {audit.potential_contradictions}")
            print(f"  Dead Edges:              {audit.dead_edges}")
            print("\nRun with --apply to compact tombstones past the 7-day retention floor.")


if __name__ == "__main__":
    main()
