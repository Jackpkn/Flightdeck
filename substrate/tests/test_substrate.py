"""Comprehensive test suite for Flightdeck Epistemic Causal Substrate (ECS)."""

from datetime import datetime, timezone, timedelta
import tempfile
from pathlib import Path
import pytest

from ecs.models import (
    AuthorityLevel,
    MemoryKind,
    LifecycleState,
    EdgeType,
    AnchorStatus,
    MemoryAnchor,
    MemoryAtom,
    MemoryEdge,
    ContradictionKind,
)
from ecs.db import ECSDatabase
from ecs.adjudication import AdjudicationEngine
from ecs.git_probe import GitProbe
from ecs.retrieval import BudgetAwareRetriever
from ecs.dream import DreamEngine


@pytest.fixture
def db():
    return ECSDatabase(":memory:")


@pytest.fixture
def adjudicator(db):
    return AdjudicationEngine(db)


@pytest.fixture
def retriever(db):
    return BudgetAwareRetriever(db)


def test_authority_quarantine(adjudicator, db):
    """External documents (L4) must be strictly quarantined."""
    atom = MemoryAtom(
        project="Flightdeck",
        file_path="Sources/Flightdeck/DevCleaner.swift",
        kind=MemoryKind.RULE,
        authority=AuthorityLevel.L4,
        trigger_pattern="StackOverflow recommendation",
        resolution="Delete ~/.cargo directly",
    )

    persisted, affected, edges = adjudicator.adjudicate_write(atom)
    assert persisted.state == LifecycleState.QUARANTINED
    assert persisted.confidence < 0.5
    assert persisted.label == "quarantined"

    # Must NOT be returned in active queries
    active = db.fetch_atoms(project="Flightdeck", active_only=True)
    assert len(active) == 0

    all_atoms = db.fetch_atoms(project="Flightdeck", active_only=False)
    assert len(all_atoms) == 1
    assert all_atoms[0].state == LifecycleState.QUARANTINED


def test_cupmem_supersedes_conflict(adjudicator, db):
    """New verified compiler evidence supersedes older agent assumption."""
    old_atom = MemoryAtom(
        project="Flightdeck",
        file_path="Sources/Flightdeck/DevCleaner.swift",
        symbol="CargoCleaner",
        kind=MemoryKind.TRAP,
        authority=AuthorityLevel.L2,
        trigger_pattern="Cargo registry cache cleanup",
        resolution="Clean ~/.cargo/cache",
    )
    old_atom, _, _ = adjudicator.adjudicate_write(old_atom)
    assert old_atom.state == LifecycleState.ACTIVE

    # Compiler output (L1) correcting path
    new_atom = MemoryAtom(
        project="Flightdeck",
        file_path="Sources/Flightdeck/DevCleaner.swift",
        symbol="CargoCleaner",
        kind=MemoryKind.RULE,
        authority=AuthorityLevel.L1,
        trigger_pattern="Cargo registry cache cleanup",
        resolution="Cargo caches live in ~/.cargo/registry/cache, not ~/.cargo/cache",
    )
    new_atom, affected, edges = adjudicator.adjudicate_write(new_atom)

    assert new_atom.state == LifecycleState.ACTIVE
    assert len(affected) == 1
    reloaded_old = db.get_atom(old_atom.id)
    assert reloaded_old.state == LifecycleState.SUPERSEDED
    assert reloaded_old.invalidated_by == new_atom.id
    assert reloaded_old.valid_until is not None

    # Check SUPERSEDES edge
    assert len(edges) == 1
    assert edges[0].edge_type == EdgeType.SUPERSEDES
    assert edges[0].from_atom_id == new_atom.id
    assert edges[0].to_atom_id == old_atom.id


def test_cross_agent_contradiction_conflict_directive(adjudicator, db):
    """Two L2 agents with conflicting claims produce CONFLICTED state & dual directive."""
    atom_a = MemoryAtom(
        project="Flightdeck",
        file_path="Sources/Flightdeck/App.swift",
        subject="DatabasePath",
        predicate="location",
        object_value="~/.flightdeck/flightdeck.sqlite",
        kind=MemoryKind.RULE,
        authority=AuthorityLevel.L2,
        trigger_pattern="database path configuration",
        resolution="Use ~/.flightdeck/flightdeck.sqlite",
        session_id="session_2026-01",
    )
    atom_a, _, _ = adjudicator.adjudicate_write(atom_a)

    atom_b = MemoryAtom(
        project="Flightdeck",
        file_path="Sources/Flightdeck/App.swift",
        subject="DatabasePath",
        predicate="location",
        object_value="~/Library/Application Support/Flightdeck/",
        kind=MemoryKind.RULE,
        authority=AuthorityLevel.L2,
        trigger_pattern="database path configuration",
        resolution="Use ~/Library/Application Support/Flightdeck/",
        session_id="session_2026-02",
    )
    atom_b, affected, edges = adjudicator.adjudicate_write(atom_b)

    reloaded_a = db.get_atom(atom_a.id)
    assert reloaded_a.state == LifecycleState.CONFLICTED
    assert atom_b.state == LifecycleState.CONFLICTED

    # Explicit CONTRADICTS edge
    assert any(e.edge_type == EdgeType.CONTRADICTS for e in edges)

    # Micro-directive must format conflict variant explicitly
    directive = atom_b.micro_directive
    assert "[CONFLICT: DatabasePath]" in directive
    assert "Two sources disagree" in directive
    assert "Session session_2026-01" in directive
    assert "Session session_2026-02" in directive


def test_hash_anchored_symbol_verification():
    """Hash-anchored verification distinguishes verified, stale, and contradicted."""
    with tempfile.TemporaryDirectory() as tmpdir:
        root = Path(tmpdir)
        test_file = root / "DevCleaner.swift"
        test_file.write_text("class ContextWindowSource {\n    static let statusline = 1\n}")

        blob = test_file.read_bytes()
        initial_hash = GitProbe.sha256_bytes(blob)

        anchor = MemoryAnchor(
            file_path="DevCleaner.swift",
            symbol_name="ContextWindowSource",
            content_hash=initial_hash,
        )

        # 1. Exact hash matches -> VERIFIED
        res1 = GitProbe.verify_anchor(anchor, root)
        assert res1.status == AnchorStatus.VERIFIED

        # 2. File modified, but symbol persists -> STALE
        test_file.write_text("class ContextWindowSource {\n    static let statusline = 2\n    static let newMember = 3\n}")
        res2 = GitProbe.verify_anchor(anchor, root)
        assert res2.status == AnchorStatus.STALE

        # 3. Symbol removed -> CONTRADICTED
        test_file.write_text("class RefactoredWindowSource {\n    static let statusline = 2\n}")
        res3 = GitProbe.verify_anchor(anchor, root)
        assert res3.status == AnchorStatus.CONTRADICTED

        # 4. File deleted -> MISSING_SOURCE
        test_file.unlink()
        res4 = GitProbe.verify_anchor(anchor, root)
        assert res4.status == AnchorStatus.MISSING_SOURCE


def test_fts5_porter_search_and_staleness_penalty(db):
    """FTS5 search with Porter stemming ranks matches and applies staleness penalties."""
    # Insert active atom
    active_atom = MemoryAtom(
        project="Flightdeck",
        file_path="Sources/Flightdeck/DevCleaner.swift",
        symbol="CargoCacheCleaner",
        kind=MemoryKind.TRAP,
        trigger_pattern="cleaning cargo registry caches",
        resolution="Use cargo registry cache path",
        state=LifecycleState.ACTIVE,
        anchor_status=AnchorStatus.VERIFIED,
    )
    db.save_atom(active_atom)

    # Insert stale atom
    stale_atom = MemoryAtom(
        project="Flightdeck",
        file_path="Sources/Flightdeck/Other.swift",
        symbol="CargoOld",
        kind=MemoryKind.TRAP,
        trigger_pattern="cleaning cargo old caches",
        resolution="Delete old cargo path",
        state=LifecycleState.STALE,
        anchor_status=AnchorStatus.STALE,
    )
    db.save_atom(stale_atom)

    # Search using stemmed word "clean"
    matches = db.search_fts(
        query_text="clean cargo",
        project="Flightdeck",
        active_files=["Sources/Flightdeck/DevCleaner.swift"],
    )

    assert len(matches) == 2
    top_atom, top_score = matches[0]
    # Active atom with file overlap must rank higher than stale atom
    assert top_atom.id == active_atom.id
    assert top_score > matches[1][1]


def test_on_demand_retrieval_blocks_contradicted_and_reports_drift(db):
    """Retrieval on-demand verification blocks contradicted memories and includes drift report."""
    with tempfile.TemporaryDirectory() as tmpdir:
        root = Path(tmpdir)
        test_file = root / "DevCleaner.swift"
        test_file.write_text("class MissingSymbolHere {}")
        current_hash = GitProbe.sha256_bytes(test_file.read_bytes())

        # Atom references obsolete symbol 'ContextWindowSource'
        contradicted_atom = MemoryAtom(
            project="Flightdeck",
            file_path="DevCleaner.swift",
            symbol="ContextWindowSource",
            kind=MemoryKind.TRAP,
            trigger_pattern="compiler error on ContextWindowSource",
            resolution="Use .statusline",
            anchor=MemoryAnchor(
                file_path="DevCleaner.swift",
                symbol_name="ContextWindowSource",
                content_hash="old_fake_hash_12345",
            ),
        )
        db.save_atom(contradicted_atom)

        retriever = BudgetAwareRetriever(db, repo_root=root)
        resp = retriever.query(
            project="Flightdeck",
            file_paths=["DevCleaner.swift"],
            intent="ContextWindowSource",
        )

        # Contradicted atom MUST be blocked from being served as fact
        assert len(resp.results) == 0
        assert resp.status == "UNKNOWN"
        assert resp.drift is not None
        assert resp.drift["contradicted"] == 1


def test_bitemporal_blast_radius_cte(db):
    """Recursive CTE correctly navigates causal dependencies."""
    atom_a = MemoryAtom(
        id="atom-A",
        project="Flightdeck",
        file_path="A.swift",
        kind=MemoryKind.TRAP,
        trigger_pattern="trigger A",
        resolution="fix A",
    )
    atom_b = MemoryAtom(
        id="atom-B",
        project="Flightdeck",
        file_path="B.swift",
        kind=MemoryKind.INVARIANT,
        trigger_pattern="trigger B",
        resolution="fix B",
    )
    atom_c = MemoryAtom(
        id="atom-C",
        project="Flightdeck",
        file_path="C.swift",
        kind=MemoryKind.RULE,
        trigger_pattern="trigger C",
        resolution="fix C",
    )

    db.save_atom(atom_a)
    db.save_atom(atom_b)
    db.save_atom(atom_c)

    db.save_edge(MemoryEdge(
        from_atom_id=atom_a.id,
        to_atom_id=atom_b.id,
        edge_type=EdgeType.CAUSES,
    ))
    db.save_edge(MemoryEdge(
        from_atom_id=atom_b.id,
        to_atom_id=atom_c.id,
        edge_type=EdgeType.DEPENDS_ON,
    ))

    # Fix solves atom_a (fix -> problem)
    atom_fix = MemoryAtom(
        id="atom-Fix",
        project="Flightdeck",
        file_path="Fix.swift",
        kind=MemoryKind.RULE,
        trigger_pattern="trigger fix",
        resolution="apply fix",
    )
    db.save_atom(atom_fix)
    db.save_edge(MemoryEdge(
        from_atom_id=atom_fix.id,
        to_atom_id=atom_a.id,
        edge_type=EdgeType.SOLVES,
    ))

    # Blast radius from atom-A traverses outgoing CAUSES -> atom-B -> atom-C,
    # AND incoming SOLVES -> atom-Fix!
    blast_from_a = db.compute_blast_radius("atom-A", max_depth=3)
    assert set(blast_from_a) == {"atom-B", "atom-C", "atom-Fix"}

    # Blast radius from atom-Fix traverses outgoing SOLVES -> atom-A -> atom-B -> atom-C
    blast_from_fix = db.compute_blast_radius("atom-Fix", max_depth=3)
    assert set(blast_from_fix) == {"atom-A", "atom-B", "atom-C"}


def test_dream_consolidation_guardrails(db):
    """Dream consolidation respects 7-day retention floor and kill-switch."""
    dreamer = DreamEngine(db)

    fresh_atom = MemoryAtom(
        project="Flightdeck",
        file_path="A.swift",
        kind=MemoryKind.TRAP,
        trigger_pattern="t1",
        resolution="r1",
        state=LifecycleState.STALE,
        updated_at=datetime.now(timezone.utc) - timedelta(days=1),
    )
    db.save_atom(fresh_atom)

    old_atom = MemoryAtom(
        project="Flightdeck",
        file_path="B.swift",
        kind=MemoryKind.TRAP,
        trigger_pattern="t2",
        resolution="r2",
        state=LifecycleState.SUPERSEDED,
        updated_at=datetime.now(timezone.utc) - timedelta(days=10),
    )
    db.save_atom(old_atom)

    audit = dreamer.audit(project="Flightdeck")
    assert audit.tombstones_past_retention == 1

    res = dreamer.apply(project="Flightdeck")
    assert res["status"] == "APPLIED"
    assert res["compacted_tombstones"] == 1

    assert db.get_atom(fresh_atom.id) is not None
    assert db.get_atom(old_atom.id) is None


def test_mcp_server_tools():
    """Verify MCP tools run and serialize correctly."""
    from ecs.server import create_mcp_server

    server = create_mcp_server(":memory:")
    assert server.name == "flightdeck-ecs"

    tool_names = [t.name for t in server._tool_manager.list_tools()]
    assert "memory_context" in tool_names
    assert "memory_store" in tool_names
    assert "memory_search" in tool_names
    assert "memory_resolve" in tool_names
    assert "memory_status" in tool_names
    assert "memory_dream" in tool_names


def test_unresolved_conflict_90_day_aging_policy(db):
    """Unresolved equal-authority conflicts older than 90 days are archived to obsolete."""
    dreamer = DreamEngine(db)

    old_conflict = MemoryAtom(
        id="conflict-old",
        project="Flightdeck",
        file_path="Config.swift",
        kind=MemoryKind.RULE,
        trigger_pattern="database path",
        resolution="use ~/.flightdeck",
        state=LifecycleState.CONFLICTED,
        conflict_note="Unresolved L2 dispute",
        updated_at=datetime.now(timezone.utc) - timedelta(days=95),
    )
    recent_conflict = MemoryAtom(
        id="conflict-recent",
        project="Flightdeck",
        file_path="Config.swift",
        kind=MemoryKind.RULE,
        trigger_pattern="database path",
        resolution="use ~/Library/Support",
        state=LifecycleState.CONFLICTED,
        conflict_note="Recent dispute",
        updated_at=datetime.now(timezone.utc) - timedelta(days=10),
    )
    db.save_atom(old_conflict)
    db.save_atom(recent_conflict)

    audit = dreamer.audit(project="Flightdeck")
    assert audit.aged_conflicts_eligible == 1

    res = dreamer.apply(project="Flightdeck")
    assert res["status"] == "APPLIED"

    archived = db.get_atom("conflict-old")
    assert archived.state == LifecycleState.OBSOLETE
    assert "[Archived: unresolved after 90 days]" in archived.conflict_note

    recent = db.get_atom("conflict-recent")
    assert recent.state == LifecycleState.CONFLICTED


def test_reverification_stale_dependents_recovery(db):
    """Stale dependent atom recovers to active when verified against repository code."""
    with tempfile.TemporaryDirectory() as tmpdir:
        repo_root = Path(tmpdir)
        import subprocess
        subprocess.run(["git", "-C", str(repo_root), "init"], check=True, capture_output=True)
        subprocess.run(["git", "-C", str(repo_root), "config", "user.name", "Test"], check=True, capture_output=True)
        subprocess.run(["git", "-C", str(repo_root), "config", "user.email", "test@example.com"], check=True, capture_output=True)

        worker_file = repo_root / "Worker.swift"
        worker_file.write_text("class WorkerService {\n    func execute() { print(\"running\") }\n}\n")
        subprocess.run(["git", "-C", str(repo_root), "add", "."], check=True, capture_output=True)
        subprocess.run(["git", "-C", str(repo_root), "commit", "-m", "Initial commit"], check=True, capture_output=True)

        premise_old = MemoryAtom(
            id="premise-old",
            project="Flightdeck",
            file_path="Config.swift",
            kind=MemoryKind.RULE,
            trigger_pattern="config",
            resolution="old config",
            state=LifecycleState.SUPERSEDED,
            invalidated_by="premise-new",
        )
        premise_new = MemoryAtom(
            id="premise-new",
            project="Flightdeck",
            file_path="Config.swift",
            kind=MemoryKind.RULE,
            trigger_pattern="config",
            resolution="new config",
            state=LifecycleState.ACTIVE,
        )
        deduction = MemoryAtom(
            id="deduction-stale",
            project="Flightdeck",
            file_path="Worker.swift",
            symbol="WorkerService",
            kind=MemoryKind.RULE,
            trigger_pattern="WorkerService",
            resolution="call execute",
            state=LifecycleState.STALE,
            anchor_status=AnchorStatus.STALE,
            conflict_note="Premise was superseded",
        )
        db.save_atom(premise_old)
        db.save_atom(premise_new)
        db.save_atom(deduction)
        db.save_edge(MemoryEdge(from_atom_id=deduction.id, to_atom_id=premise_old.id, edge_type=EdgeType.DEPENDS_ON))

        recovered, remained = GitProbe.reverify_stale_dependents(db, repo_root, project="Flightdeck")
        assert recovered == 1
        assert remained == 0

        reloaded = db.get_atom("deduction-stale")
        assert reloaded.state == LifecycleState.ACTIVE
        assert reloaded.anchor_status == AnchorStatus.VERIFIED
        assert "✓ Re-verified" in reloaded.conflict_note


def test_blast_radius_semantic_limit_cutoff(db):
    """Blast radius CTE respects semantic limit cutoff parameter."""
    # Create a chain of 10 nodes
    for i in range(10):
        db.save_atom(MemoryAtom(
            id=f"chain-{i}",
            project="Flightdeck",
            file_path=f"F{i}.swift",
            kind=MemoryKind.RULE,
            trigger_pattern=f"t{i}",
            resolution=f"r{i}",
            state=LifecycleState.ACTIVE,
        ))
        if i > 0:
            db.save_edge(MemoryEdge(
                from_atom_id=f"chain-{i-1}",
                to_atom_id=f"chain-{i}",
                edge_type=EdgeType.DEPENDS_ON,
            ))

    # Without tight limit
    full_blast = db.compute_blast_radius("chain-0", max_depth=10, limit=20)
    assert len(full_blast) == 9
    assert not full_blast.truncated
    assert full_blast.total_estimate == 9

    # With limit=3
    limited_blast = db.compute_blast_radius("chain-0", max_depth=10, limit=3)
    assert len(limited_blast) == 3
    assert limited_blast.truncated
    assert limited_blast.total_estimate == 9


def test_adversarial_content_dependency_rewiring_caveat(tmp_path):
    """
    Adversarial rewiring test:
    When premise C (StorageX) is superseded by C' (StorageY),
    if dependent D asserted specific content/symbols of StorageX that are absent
    in StorageY, re-verification must NOT falsely un-stale D.
    D must remain STALE because its claim cannot be verified against code.
    """
    db = ECSDatabase(":memory:")

    # Repo only has StorageY with ModernStorageService, NOT LegacyTable
    y_file = tmp_path / "StorageY.swift"
    y_file.write_text("class ModernStorageService { func query() {} }\n")

    c_old = MemoryAtom(
        id="premise-old",
        project="Flightdeck",
        file_path="StorageX.swift",
        symbol="StorageEngine",
        kind=MemoryKind.RULE,
        trigger_pattern="storage",
        resolution="old",
        state=LifecycleState.SUPERSEDED,
        invalidated_by="premise-new",
    )
    c_new = MemoryAtom(
        id="premise-new",
        project="Flightdeck",
        file_path="StorageY.swift",
        symbol="ModernStorageService",
        kind=MemoryKind.RULE,
        trigger_pattern="storage",
        resolution="new",
        state=LifecycleState.ACTIVE,
    )
    d_dependent = MemoryAtom(
        id="deduction-legacy-content",
        project="Flightdeck",
        file_path="StorageY.swift",
        symbol="LegacyTable",
        kind=MemoryKind.RULE,
        trigger_pattern="query table",
        resolution="legacy table query",
        state=LifecycleState.STALE,
        anchor_status=AnchorStatus.STALE,
        conflict_note="Dependency was superseded",
    )

    db.save_atom(c_old)
    db.save_atom(c_new)
    db.save_atom(d_dependent)
    db.save_edge(MemoryEdge(
        from_atom_id=d_dependent.id,
        to_atom_id=c_old.id,
        edge_type=EdgeType.DEPENDS_ON,
    ))

    # Run re-verification loop
    from ecs.git_probe import GitProbe
    recovered, remained = GitProbe.reverify_stale_dependents(db, tmp_path, project="Flightdeck")

    assert recovered == 0
    assert remained == 1

    reloaded = db.get_atom("deduction-legacy-content")
    assert reloaded.state == LifecycleState.STALE
    assert reloaded.anchor_status != AnchorStatus.VERIFIED


def test_double_verification_promotion_and_differing_fix(db):
    """
    Transcript miner candidate memories enter as L2 hypotheses.
    Second observation in a different session with matching fix promotes to ACTIVE (0.95 confidence).
    Recurrence with a differing fix invalidates prior candidate and creates CONTRADICTS edge.
    """
    engine = AdjudicationEngine(db)

    # 1. First observation from transcript miner in Session A
    cand1 = MemoryAtom(
        id="cand-obs-1",
        project="Flightdeck",
        file_path="Sources/Flightdeck/DevCleaner.swift",
        kind=MemoryKind.TRAP,
        trigger_pattern=".measured",
        failure_signature="type ContextWindowSource has no member 'measured'",
        resolution="Valid cases are .statusline, .inferred, .fallback",
        session_id="session-aaa",
        source="transcript_miner",
    )
    atom1, affected1, edges1 = engine.adjudicate_write(cand1)

    assert atom1.state == LifecycleState.CANDIDATE
    assert atom1.authority == AuthorityLevel.L2
    assert atom1.confidence == 0.60

    # 2. Second observation from transcript miner in Session B with SAME fix
    cand2 = MemoryAtom(
        id="cand-obs-2",
        project="Flightdeck",
        file_path="Sources/Flightdeck/DevCleaner.swift",
        kind=MemoryKind.TRAP,
        trigger_pattern=".measured",
        failure_signature="type ContextWindowSource has no member 'measured'",
        resolution="Valid cases are .statusline, .inferred, .fallback",
        session_id="session-bbb",
        source="transcript_miner",
    )
    atom2, affected2, edges2 = engine.adjudicate_write(cand2)

    # First atom promoted to verified active!
    promoted = db.get_atom("cand-obs-1")
    assert promoted.state == LifecycleState.ACTIVE
    assert promoted.confidence == 0.95
    assert promoted.hit_count >= 1
    assert any(e.edge_type == EdgeType.EVIDENCE_FOR for e in edges2)

    # 3. Third observation in Session C with a DIFFERENT fix (recurrence with different fix)
    cand3 = MemoryAtom(
        id="cand-obs-3",
        project="Flightdeck",
        file_path="Sources/Flightdeck/DevCleaner.swift",
        kind=MemoryKind.TRAP,
        trigger_pattern=".measured",
        failure_signature="type ContextWindowSource has no member 'measured'",
        resolution="Replace enum reference with raw string value",
        session_id="session-ccc",
        source="transcript_miner",
    )
    atom3, affected3, edges3 = engine.adjudicate_write(cand3)

    # Promoted old atom is invalidated by the differing fix
    promoted_superseded = db.get_atom("cand-obs-1")
    assert promoted_superseded.state == LifecycleState.SUPERSEDED
    assert promoted_superseded.invalidated_by == "cand-obs-3"
    assert any(e.edge_type == EdgeType.CONTRADICTS for e in edges3)

    # New observation is a candidate hypothesis
    assert atom3.state == LifecycleState.CANDIDATE
    assert atom3.confidence == 0.60

