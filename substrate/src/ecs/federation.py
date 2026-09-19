"""Decentralized Git Federation & Team Sync for Flightdeck ECS Memory."""

from __future__ import annotations
import json
import os
from pathlib import Path
from typing import Any

from .models import (
    LifecycleState,
    MemoryAtom,
    MemoryEdge,
)
from .db import ECSDatabase
from .adjudication import AdjudicationEngine


DEFAULT_FEDERATION_REL_PATH = Path(".flightdeck") / "memory"


def get_default_federation_dir(repo_root: Path | str | None = None) -> Path:
    """Returns the default .flightdeck/memory directory within the repository root."""
    root = Path(repo_root or ".").resolve()
    return root / DEFAULT_FEDERATION_REL_PATH


def export_memory(
    db: ECSDatabase,
    output_dir: Path | str,
    project: str | None = None,
) -> tuple[int, int]:
    """
    Exports verified active and conflicted memory atoms and causal edges to line-delimited JSON (JSONL).
    Sorted deterministically to ensure clean, human-readable Git diffs.
    Uses atomic writes (.tmp -> atomic rename) to avoid partial state corruption.
    """
    out_path = Path(output_dir)
    out_path.mkdir(parents=True, exist_ok=True)

    atoms_file = out_path / "atoms.jsonl"
    edges_file = out_path / "edges.jsonl"

    # 1. Fetch eligible atoms
    all_atoms = db.fetch_atoms(project=project, active_only=False)
    exportable_atoms = [
        a for a in all_atoms
        if a.state in (LifecycleState.ACTIVE, LifecycleState.CONFLICTED)
        and not a.authority.is_quarantined
    ]

    # Deterministic sort order: file_path ASC, symbol ASC, trigger_pattern ASC, id ASC
    exportable_atoms.sort(key=lambda a: (a.file_path, a.symbol or "", a.trigger_pattern, a.id))

    # Atomic write atoms
    tmp_atoms = out_path / "atoms.jsonl.tmp"
    with open(tmp_atoms, "w", encoding="utf-8") as f:
        for atom in exportable_atoms:
            f.write(json.dumps(atom.to_dict(), sort_keys=True) + "\n")
    os.replace(tmp_atoms, atoms_file)

    # 2. Fetch and export active causal edges
    cur = db._conn.cursor()
    cur.execute("SELECT * FROM memory_edges WHERE valid_until IS NULL")
    edge_rows = cur.fetchall()
    edges = [db._row_to_edge(r) for r in edge_rows]

    # Filter to edges whose endpoints are in exportable atoms
    exportable_ids = {a.id for a in exportable_atoms}
    exportable_edges = [
        e for e in edges
        if e.from_atom_id in exportable_ids and e.to_atom_id in exportable_ids
    ]
    exportable_edges.sort(key=lambda e: (e.from_atom_id, e.to_atom_id, e.edge_type.value, e.id))

    tmp_edges = out_path / "edges.jsonl.tmp"
    with open(tmp_edges, "w", encoding="utf-8") as f:
        for edge in exportable_edges:
            f.write(json.dumps(edge.to_dict(), sort_keys=True) + "\n")
    os.replace(tmp_edges, edges_file)

    return len(exportable_atoms), len(exportable_edges)


def import_memory(
    db: ECSDatabase,
    input_dir: Path | str,
    project: str | None = None,
) -> dict[str, int]:
    """
    Imports memory atoms and edges from .flightdeck/memory JSONL files.
    Applies write-side adjudication (Gate 3 CUPMem) against existing local memories
    so that incoming teammate memories merge gracefully or flag CONFLICTED if contradictory.
    """
    in_path = Path(input_dir)
    atoms_file = in_path / "atoms.jsonl"
    edges_file = in_path / "edges.jsonl"

    if not atoms_file.exists():
        return {"imported": 0, "updated": 0, "conflicted": 0, "skipped": 0, "edges_imported": 0}

    adjudicator = AdjudicationEngine(db)
    imported = 0
    updated = 0
    conflicted = 0
    skipped = 0

    with open(atoms_file, "r", encoding="utf-8") as f:
        for line in f:
            line_str = line.strip()
            if not line_str:
                continue
            data = json.loads(line_str)
            atom = MemoryAtom.from_dict(data)

            if project and atom.project != project:
                skipped += 1
                continue

            existing = db.get_atom(atom.id)
            if existing:
                # Same ID already present: update if incoming has newer updated_at or higher authority
                if atom.authority.trust_score > existing.authority.trust_score or atom.updated_at > existing.updated_at:
                    db.save_atom(atom)
                    updated += 1
                else:
                    skipped += 1
            else:
                # New atom: pass through write-side adjudication for slot conflicts
                persisted, affected, _ = adjudicator.adjudicate_write(atom)
                if persisted.state == LifecycleState.CONFLICTED:
                    conflicted += 1
                else:
                    imported += 1

    # Import edges
    edges_imported = 0
    if edges_file.exists():
        with open(edges_file, "r", encoding="utf-8") as f:
            for line in f:
                line_str = line.strip()
                if not line_str:
                    continue
                data = json.loads(line_str)
                edge = MemoryEdge.from_dict(data)
                # Verify both endpoints exist before saving
                if db.get_atom(edge.from_atom_id) and db.get_atom(edge.to_atom_id):
                    db.save_edge(edge)
                    edges_imported += 1

    return {
        "imported": imported,
        "updated": updated,
        "conflicted": conflicted,
        "skipped": skipped,
        "edges_imported": edges_imported,
    }


def sync_memory(
    db: ECSDatabase,
    repo_root: Path | str | None = None,
    project: str | None = None,
) -> dict[str, Any]:
    """
    Two-way synchronization between local SQLite database and Git repository JSONL files.
    1. Imports any new/updated memories committed by teammates in .flightdeck/memory/.
    2. Exports local active/conflicted memories back to .flightdeck/memory/ for committing.
    """
    federation_dir = get_default_federation_dir(repo_root)
    federation_dir.mkdir(parents=True, exist_ok=True)

    import_stats = import_memory(db, federation_dir, project=project)
    exported_atoms, exported_edges = export_memory(db, federation_dir, project=project)

    return {
        "federation_dir": str(federation_dir),
        "imported": import_stats["imported"],
        "updated": import_stats["updated"],
        "conflicts": import_stats["conflicted"],
        "edges_imported": import_stats["edges_imported"],
        "exported_atoms": exported_atoms,
        "exported_edges": exported_edges,
    }
