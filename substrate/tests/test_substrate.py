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
    assert atom1.authority == AuthorityLevel.L2b
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


def test_gate2_quality_filters_identifier_and_trigger_match(adjudicator, db):
    """Gate 2 enforces structural code identifiers, routes unpatterned advice, and discards platitudes."""
    # 1. Pure platitude ('try again and be careful') -> discarded
    vague_atom = MemoryAtom(
        project="Flightdeck",
        file_path="Sources/Flightdeck/App.swift",
        kind=MemoryKind.RULE,
        trigger_pattern="database lock error",
        resolution="try again and be careful",
        authority=AuthorityLevel.L2,
    )
    sig_vague = adjudicator.verify_candidate(vague_atom)
    assert sig_vague.label == "trivial_platitude_discarded"
    assert sig_vague.confidence <= 0.30

    # 2. Actionable unpatterned resolution without explicit identifier tokens -> routes to pending_adjudication
    unpatterned_atom = MemoryAtom(
        project="Flightdeck",
        file_path="Sources/Flightdeck/App.swift",
        kind=MemoryKind.RULE,
        trigger_pattern="order of evaluation failure",
        resolution="Move the initialization before the guard clause",
        authority=AuthorityLevel.L2,
    )
    sig_unpatterned = adjudicator.verify_candidate(unpatterned_atom)
    assert sig_unpatterned.label == "unpatterned_resolution_pending_adjudication"
    assert unpatterned_atom.state == LifecycleState.PENDING_ADJUDICATION
    assert sig_unpatterned.confidence == 0.55

    # 3. Resolution with structural code identifier ('.statusline') -> verified active
    valid_atom = MemoryAtom(
        project="Flightdeck",
        file_path="Sources/Flightdeck/ClaudeUsageMath.swift",
        kind=MemoryKind.RULE,
        trigger_pattern=".measured",
        failure_signature="type ContextWindowSource has no member 'measured'",
        resolution="Valid cases are .statusline, .inferred, .fallback",
        authority=AuthorityLevel.L2,
    )
    sig_valid = adjudicator.verify_candidate(valid_atom)
    assert sig_valid.label == "verified_success"
    assert sig_valid.confidence >= 0.80

    # 4. Hallucinated trigger not in failure signature -> trigger_not_found_in_error
    hallucinated_atom = MemoryAtom(
        project="Flightdeck",
        file_path="Sources/Flightdeck/ClaudeUsageMath.swift",
        kind=MemoryKind.TRAP,
        trigger_pattern="unrelated_function_xyz",
        failure_signature="type ContextWindowSource has no member 'measured'",
        resolution="Use .statusline instead",
        authority=AuthorityLevel.L2,
    )
    sig_hallucinated = adjudicator.verify_candidate(hallucinated_atom)
    assert sig_hallucinated.label == "trigger_not_found_in_error"
    assert sig_hallucinated.confidence <= 0.45


def test_gate2_multi_file_attribution_guard(adjudicator, db):
    """Gate 2 flags ambiguous causal attribution when multiple files changed between failure and pass."""
    multi_file_candidate = MemoryAtom(
        project="Flightdeck",
        file_path="Sources/Flightdeck/DevCleaner.swift",
        kind=MemoryKind.TRAP,
        trigger_pattern="linker error",
        resolution="Update Package.swift dependencies and clean cache",
        source="transcript_miner",
        evidence_refs=["Sources/Flightdeck/DevCleaner.swift", "Package.swift"],
    )
    sig = adjudicator.verify_candidate(multi_file_candidate)
    assert multi_file_candidate.state == LifecycleState.PENDING_ADJUDICATION
    assert sig.label == "ambiguous_causal_attribution"
    assert sig.confidence == 0.50


def test_gate4_host_agent_adjudication_bounded_scope(adjudicator, db):
    """Gate 4 resolves deferred decisions via host agent MCP tool with full provenance tracking."""
    # Setup candidate sitting in pending_adjudication
    candidate = MemoryAtom(
        id="pending-cand-42",
        project="Flightdeck",
        file_path="Sources/Flightdeck/DevCleaner.swift",
        kind=MemoryKind.TRAP,
        trigger_pattern="linker error symbol not found",
        resolution="Add GRDB dependency to Package.swift",
        state=LifecycleState.PENDING_ADJUDICATION,
        source="transcript_miner",
        verified_by="transcript_miner",
        evidence_refs=["Sources/Flightdeck/DevCleaner.swift", "Package.swift"],
    )
    db.save_atom(candidate)

    # 1. Question 1: Host agent adjudicates multi-file causal attribution
    res_attr = adjudicator.adjudicate_host_agent(
        candidate_id="pending-cand-42",
        host_agent="claude_code",
        decision="attribute",
        reason="Package.swift target dependency addition was the actual causal fix",
        target_file="Package.swift",
    )
    assert res_attr["status"] == "ADJUDICATED"
    assert res_attr["verified_by"] == "host_agent:claude_code"
    reloaded = db.get_atom("pending-cand-42")
    assert reloaded.state == LifecycleState.ACTIVE
    assert reloaded.file_path == "Package.swift"
    assert reloaded.verified_by == "host_agent:claude_code"
    assert reloaded.confidence >= 0.85

    # 2. Question 2: Host agent re-verifies content dependency (valid)
    res_valid = adjudicator.adjudicate_host_agent(
        candidate_id="pending-cand-42",
        host_agent="claude_code",
        decision="valid",
        reason="GRDB import persists in target after refactoring",
    )
    assert res_valid["status"] == "ADJUDICATED"

    # 3. Question 2 (refuted): Content dependency broken (invalid/stale)
    res_stale = adjudicator.adjudicate_host_agent(
        candidate_id="pending-cand-42",
        host_agent="claude_code",
        decision="stale",
        reason="GRDB removed in favor of SQLite3 C bindings",
    )
    assert res_stale["status"] == "ADJUDICATED"
    reloaded_stale = db.get_atom("pending-cand-42")
    assert reloaded_stale.state == LifecycleState.STALE
    assert reloaded_stale.valid_until is not None

    # 4. Question 3: UNKNOWN conflict resolution (distinct scope)
    res_scope = adjudicator.adjudicate_host_agent(
        candidate_id="pending-cand-42",
        host_agent="cursor",
        decision="distinct_scope",
        reason="Applies only on macOS 14+, Linux builds use alternate stub",
    )
    assert res_scope["status"] == "ADJUDICATED"
    assert res_scope["verified_by"] == "host_agent:cursor"

    # 5. Out of bounds decision -> retained in pending_adjudication for human review
    res_oob = adjudicator.adjudicate_host_agent(
        candidate_id="pending-cand-42",
        host_agent="claude_code",
        decision="arbitrary_unbounded_decision",
        reason="I think we should rewrite the module",
    )
    assert res_oob["status"] == "PENDING_HUMAN_REVIEW"
    reloaded_oob = db.get_atom("pending-cand-42")
    assert reloaded_oob.state == LifecycleState.PENDING_ADJUDICATION


def test_dream_phase_miner_candidate_reconciliation(adjudicator, db):
    """The Dream Phase asynchronously runs Gate 3 on background miner candidate atoms."""
    from ecs.dream import DreamEngine
    dreamer = DreamEngine(db)

    # Miner writes a candidate hypothesis
    cand = MemoryAtom(
        id="miner-cand-101",
        project="Flightdeck",
        file_path="Sources/Flightdeck/DevCleaner.swift",
        kind=MemoryKind.TRAP,
        trigger_pattern=".measured",
        failure_signature="type ContextWindowSource has no member 'measured'",
        resolution="Valid cases are .statusline, .inferred, .fallback",
        state=LifecycleState.CANDIDATE,
        source="transcript_miner",
    )
    db.save_atom(cand)

    # Dream audit reports pending candidate
    audit = dreamer.audit(project="Flightdeck")
    assert audit.pending_candidates >= 1

    # Dream apply runs Gate 3 reconciliation
    report = dreamer.apply(project="Flightdeck")
    assert report["reconciled_candidates"] >= 1


def test_provisional_trial_period_demoted_on_contradiction(adjudicator, db):
    """Host-agent adjudicated atoms enter active with a 7-day trial period; contradiction demotes them."""
    # 1. Candidate is adjudicated active by host agent -> enters with provisional trial_until
    cand = MemoryAtom(
        id="provisional-atom-1",
        project="Flightdeck",
        file_path="Sources/Flightdeck/App.swift",
        kind=MemoryKind.RULE,
        trigger_pattern="database lock error",
        resolution="Use WAL mode with 5000ms timeout",
        state=LifecycleState.PENDING_ADJUDICATION,
    )
    db.save_atom(cand)

    adj_res = adjudicator.adjudicate_host_agent(
        candidate_id="provisional-atom-1",
        host_agent="claude_code",
        decision="valid",
        reason="Verified working in test suite",
    )
    assert adj_res["status"] == "ADJUDICATED"

    active_atom = db.get_atom("provisional-atom-1")
    assert active_atom.state == LifecycleState.ACTIVE
    assert active_atom.is_provisional is True
    assert active_atom.trial_until is not None
    assert "PROVISIONAL TRIAL" in active_atom.micro_directive

    # 2. A contradiction arrives in a later session (e.g. from compiler or transcript miner)
    refuting_atom = MemoryAtom(
        id="refuting-atom-2",
        project="Flightdeck",
        file_path="Sources/Flightdeck/App.swift",
        kind=MemoryKind.RULE,
        authority=AuthorityLevel.L1,
        trigger_pattern="database lock error",
        resolution="Use in-memory lock coordinator instead of WAL timeout",
    )
    persisted, affected, edges = adjudicator.adjudicate_write(refuting_atom)

    # Because provisional-atom-1 was under provisional trial, it is demoted to pending_adjudication
    reloaded_prov = db.get_atom("provisional-atom-1")
    assert reloaded_prov.state == LifecycleState.PENDING_ADJUDICATION
    assert "Demoted from provisional active to pending_adjudication" in (reloaded_prov.conflict_note or "")


def test_peer_authority_l2a_vs_l2b_conflict(adjudicator, db):
    """When L2a (host agent) and L2b (transcript miner) contradict, neither wins; state is CONFLICTED."""
    # L2b atom stored first
    atom_l2b = MemoryAtom(
        id="peer-miner-atom",
        project="Flightdeck",
        file_path="Sources/Flightdeck/Model.swift",
        kind=MemoryKind.TRAP,
        authority=AuthorityLevel.L2b,
        verified_by="transcript_miner",
        trigger_pattern="unsupported enum value",
        resolution="Use .inferred fallback",
        state=LifecycleState.ACTIVE,
    )
    db.save_atom(atom_l2b)

    # L2a atom arrives with contradicting resolution for identical trigger
    atom_l2a = MemoryAtom(
        id="peer-agent-atom",
        project="Flightdeck",
        file_path="Sources/Flightdeck/Model.swift",
        kind=MemoryKind.TRAP,
        authority=AuthorityLevel.L2a,
        verified_by="host_agent:cursor",
        trigger_pattern="unsupported enum value",
        resolution="Use .fallback default",
    )
    persisted, affected, edges = adjudicator.adjudicate_write(atom_l2a)

    # Equal peer conflict: neither overwrites the other
    assert persisted.state == LifecycleState.CONFLICTED
    reloaded_miner = db.get_atom("peer-miner-atom")
    assert reloaded_miner.state == LifecycleState.CONFLICTED
    assert any(e.edge_type == EdgeType.CONTRADICTS for e in edges)


def test_gate4_question4_validate_advice(adjudicator, db):
    """Gate 4 Question 4 allows host agent to validate unpatterned specific advice."""
    unpatterned = MemoryAtom(
        id="unpatterned-cand-1",
        project="Flightdeck",
        file_path="Sources/Flightdeck/Config.swift",
        kind=MemoryKind.RULE,
        trigger_pattern="argument ordering bug",
        resolution="Use the second parameter instead of the first",
        state=LifecycleState.PENDING_ADJUDICATION,
    )
    db.save_atom(unpatterned)

    res = adjudicator.adjudicate_host_agent(
        candidate_id="unpatterned-cand-1",
        host_agent="claude_code",
        decision="validate_advice",
        reason="The second parameter is the destination URL while the first is the source",
    )
    assert res["status"] == "ADJUDICATED"
    reloaded = db.get_atom("unpatterned-cand-1")
    assert reloaded.state == LifecycleState.ACTIVE
    assert reloaded.is_provisional is True
    assert reloaded.verified_by == "host_agent:claude_code"


def test_retrieval_pending_adjudications_banner(db):
    """Retrieval responses include pending adjudication count and action required banner."""
    from ecs.retrieval import BudgetAwareRetriever
    retriever = BudgetAwareRetriever(db)

    # Store a pending candidate
    pending_atom = MemoryAtom(
        id="pending-notice-1",
        project="Flightdeck",
        file_path="Sources/Flightdeck/Notice.swift",
        kind=MemoryKind.TRAP,
        trigger_pattern="fatal error",
        resolution="Return nil on failure",
        state=LifecycleState.PENDING_ADJUDICATION,
    )
    db.save_atom(pending_atom)

    resp = retriever.query(project="Flightdeck", file_paths=["Sources/Flightdeck/Notice.swift"])
    assert resp.pending_adjudications_count >= 1

def test_federation_export_and_import_roundtrip(db, tmp_path):
    """Verifies that active and conflicted memories and edges are exported to JSONL and cleanly imported into a new DB."""
    from ecs.federation import export_memory, import_memory
    from ecs.db import ECSDatabase

    # Setup atoms
    atom1 = MemoryAtom(
        id="fed-atom-1",
        project="Flightdeck",
        file_path="Sources/Flightdeck/A.swift",
        symbol="ServiceA",
        kind=MemoryKind.TRAP,
        trigger_pattern="unsupported enum value",
        resolution="Use .inferred fallback",
        state=LifecycleState.ACTIVE,
        authority=AuthorityLevel.L2,
    )
    atom2 = MemoryAtom(
        id="fed-atom-2",
        project="Flightdeck",
        file_path="Sources/Flightdeck/B.swift",
        symbol="ServiceB",
        kind=MemoryKind.RULE,
        trigger_pattern="database lock",
        resolution="Use WAL mode",
        state=LifecycleState.CONFLICTED,
        conflict_note="Conflicted with alternate rule",
        authority=AuthorityLevel.L2,
    )
    atom_quarantine = MemoryAtom(
        id="fed-quarantine-3",
        project="Flightdeck",
        file_path="Sources/Flightdeck/C.swift",
        symbol="ServiceC",
        kind=MemoryKind.RULE,
        trigger_pattern="quarantined trigger",
        resolution="Do not export me",
        state=LifecycleState.ACTIVE,
        authority=AuthorityLevel.L4,  # Quarantined
    )
    db.save_atom(atom1)
    db.save_atom(atom2)
    db.save_atom(atom_quarantine)

    edge1 = MemoryEdge(
        id="fed-edge-1",
        from_atom_id=atom2.id,
        to_atom_id=atom1.id,
        edge_type=EdgeType.DEPENDS_ON,
    )
    db.save_edge(edge1)

    fed_dir = tmp_path / ".flightdeck" / "memory"
    atoms_cnt, edges_cnt = export_memory(db, fed_dir, project="Flightdeck")

    assert atoms_cnt == 2
    assert edges_cnt == 1
    assert (fed_dir / "atoms.jsonl").exists()
    assert (fed_dir / "edges.jsonl").exists()

    # Verify JSONL lines
    with open(fed_dir / "atoms.jsonl") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == 2
    # Verify deterministic sort: A.swift before B.swift
    assert "Sources/Flightdeck/A.swift" in lines[0]
    assert "Sources/Flightdeck/B.swift" in lines[1]

    # Import into fresh database
    fresh_db_file = tmp_path / "fresh_ecs.db"
    fresh_db = ECSDatabase(fresh_db_file)
    res = import_memory(fresh_db, fed_dir, project="Flightdeck")

    assert res["imported"] + res["conflicted"] == 2
    assert res["edges_imported"] == 1

    imported_atom1 = fresh_db.get_atom("fed-atom-1")
    assert imported_atom1 is not None
    assert imported_atom1.symbol == "ServiceA"
    assert imported_atom1.state == LifecycleState.ACTIVE

    imported_atom2 = fresh_db.get_atom("fed-atom-2")
    assert imported_atom2 is not None
    assert imported_atom2.symbol == "ServiceB"


def test_federation_import_conflict_adjudication(db, tmp_path):
    """Verifies that importing an atom with a contradicting fix triggers Gate 3 conflict adjudication."""
    from ecs.federation import export_memory, import_memory
    from ecs.db import ECSDatabase

    # Teammate created an atom in teammate DB
    teammate_db_file = tmp_path / "teammate_ecs.db"
    teammate_db = ECSDatabase(teammate_db_file)
    teammate_atom = MemoryAtom(
        id="teammate-atom-1",
        project="Flightdeck",
        file_path="Sources/Flightdeck/Config.swift",
        symbol="ConfigLoader",
        kind=MemoryKind.RULE,
        trigger_pattern="config syntax error",
        resolution="Use YAML format instead of JSON",
        authority=AuthorityLevel.L2a,
        state=LifecycleState.ACTIVE,
    )
    teammate_db.save_atom(teammate_atom)

    fed_dir = tmp_path / ".flightdeck" / "memory"
    export_memory(teammate_db, fed_dir, project="Flightdeck")

    # Local DB has a local atom with identical trigger but contradicting resolution
    local_atom = MemoryAtom(
        id="local-atom-1",
        project="Flightdeck",
        file_path="Sources/Flightdeck/Config.swift",
        symbol="ConfigLoader",
        kind=MemoryKind.RULE,
        trigger_pattern="config syntax error",
        resolution="Use TOML format instead of JSON",
        authority=AuthorityLevel.L2a,
        state=LifecycleState.ACTIVE,
    )
    db.save_atom(local_atom)

    # Import teammate's memory into local DB
    res = import_memory(db, fed_dir, project="Flightdeck")
    assert res["conflicted"] == 1

    # Both local and incoming should now be CONFLICTED
    reloaded_local = db.get_atom("local-atom-1")
    reloaded_incoming = db.get_atom("teammate-atom-1")

    assert reloaded_local.state == LifecycleState.CONFLICTED
    assert reloaded_incoming.state == LifecycleState.CONFLICTED


def test_federation_sync_memory(db, tmp_path):
    """Verifies two-way sync between local DB and repository .flightdeck/memory directory."""
    from ecs.federation import sync_memory

    atom = MemoryAtom(
        id="sync-atom-1",
        project="Flightdeck",
        file_path="Sources/Flightdeck/SyncTest.swift",
        kind=MemoryKind.RULE,
        trigger_pattern="sync pattern",
        resolution="sync resolution",
        state=LifecycleState.ACTIVE,
    )
    db.save_atom(atom)

    res = sync_memory(db, repo_root=tmp_path, project="Flightdeck")
    assert res["exported_atoms"] == 1
    assert (tmp_path / ".flightdeck" / "memory" / "atoms.jsonl").exists()


def test_dead_end_atom_creation_and_leads_to_dead_end_edge(db):
    """Verifies that falsified hypotheses are saved as DEAD_END atoms and linked via LEADS_TO_DEAD_END."""
    # 1. Parent trap atom
    trap = MemoryAtom(
        id="parent-trap-001",
        project="Flightdeck",
        file_path="Sources/Flightdeck/DevCleaner.swift",
        symbol="ContextWindowSource",
        kind=MemoryKind.TRAP,
        trigger_pattern=".measured",
        failure_signature="type ContextWindowSource has no member 'measured'",
        resolution="Valid cases are .statusline, .inferred, .fallback",
        state=LifecycleState.ACTIVE,
    )
    db.save_atom(trap)

    # 2. Record a dead end (failed attempt)
    de_atom, edge = db.record_dead_end(
        parent_id="parent-trap-001",
        file_path="Sources/Flightdeck/DevCleaner.swift",
        attempted_fix="Add .measured enum case to extension",
        failure_signature="cannot extend enum with new stored cases in external module",
        trigger_pattern=".measured",
        project="Flightdeck",
    )

    assert de_atom.kind == MemoryKind.DEAD_END
    assert edge is not None
    assert edge.edge_type == EdgeType.LEADS_TO_DEAD_END
    assert edge.from_atom_id == "parent-trap-001"
    assert edge.to_atom_id == de_atom.id

    # 3. Query dead ends
    dead_ends = db.fetch_dead_ends("parent-trap-001")
    assert len(dead_ends) == 1
    assert dead_ends[0].id == de_atom.id
    assert "cannot extend enum" in dead_ends[0].failure_signature

    # 4. Recursive blast radius traverses LEADS_TO_DEAD_END
    blast = db.compute_blast_radius("parent-trap-001")
    assert de_atom.id in blast.nodes


def test_retrieval_surfaces_known_dead_ends(db, tmp_path):
    """Verifies that retrieval decorates active traps with KNOWN DEAD ENDS to prevent circular loops."""
    from ecs.retrieval import BudgetAwareRetriever

    # Create dummy source file in tmp_path
    storage_file = tmp_path / "Storage.swift"
    storage_file.write_text("// DatabaseQueue\nclass DatabaseQueue {}", encoding="utf-8")

    # 1. Store trap
    trap = MemoryAtom(
        id="parent-trap-002",
        project="Flightdeck",
        file_path="Storage.swift",
        symbol="DatabaseQueue",
        kind=MemoryKind.TRAP,
        trigger_pattern="database lock error",
        failure_signature="SQLite error 5: database is locked",
        resolution="Use in-memory lock coordinator and WAL journal mode",
        state=LifecycleState.ACTIVE,
        authority=AuthorityLevel.L1,
    )
    db.save_atom(trap)

    # 2. Record two dead ends
    db.record_dead_end(
        parent_id="parent-trap-002",
        file_path="Storage.swift",
        attempted_fix="Increase WAL busy timeout to 30000ms",
        failure_signature="Still hangs UI thread under write bursts",
        project="Flightdeck",
    )
    db.record_dead_end(
        parent_id="parent-trap-002",
        file_path="Storage.swift",
        attempted_fix="Spawn separate background write thread with shared queue",
        failure_signature="Produced concurrency race condition",
        project="Flightdeck",
    )

    # 3. Retrieve
    retriever = BudgetAwareRetriever(db, repo_root=tmp_path)
    resp = retriever.query(project="Flightdeck", file_paths=["Storage.swift"])

    assert len(resp.results) == 1
    prompt = resp.formatted_prompt_block
    assert "✕ KNOWN DEAD ENDS (Do not attempt):" in prompt
    assert "Attempted: Increase WAL busy timeout to 30000ms" in prompt
    assert "Failed: Still hangs UI thread under write bursts" in prompt
    assert "Attempted: Spawn separate background write thread with shared queue" in prompt


def test_mcp_memory_record_dead_end(db):
    """Verifies the memory_record_dead_end MCP tool."""
    from ecs.server import create_mcp_server
    server = create_mcp_server(db.db_path)

    tool = server._tool_manager.get_tool("memory_record_dead_end")
    assert tool is not None

    res_json = tool.fn(
        file_path="Sources/Flightdeck/App.swift",
        attempted_fix="Force unwrap optional config pointer",
        failure_signature="Fatal error: unexpectedly found nil while unwrapping an Optional value",
        trigger_pattern="config loading",
        project="Flightdeck",
    )
    import json
    data = json.loads(res_json)
    assert data["status"] == "RECORDED"
    assert data["kind"] == "dead_end"
    assert "✕ DEAD END" in data["directive"]


def test_feedback_success_boosts_confidence_and_counts(db):
    """Success feedback increments success_count, increases confidence, and recalculates efficacy_score."""
    atom = MemoryAtom(
        id="fb-atom-1",
        project="Flightdeck",
        file_path="Sources/Network.swift",
        kind=MemoryKind.RULE,
        trigger_pattern="retry logic",
        resolution="Use exponential backoff with jitter",
        confidence=0.70,
    )
    db.save_atom(atom)

    res = db.record_feedback(atom_ids=["fb-atom-1"], outcome="success")
    assert res["status"] == "FEEDBACK_RECORDED"
    assert res["outcome"] == "success"
    assert res["updated_count"] == 1

    reloaded = db.get_atom("fb-atom-1")
    assert reloaded.success_count == 1
    assert reloaded.failure_count == 0
    assert reloaded.confidence == 0.75
    # Laplace smoothing: (1 + 1) / (1 + 0 + 2) = 2/3 = 0.667
    assert round(reloaded.efficacy_score, 3) == 0.667
    assert reloaded.last_feedback_at is not None


def test_feedback_failure_penalizes_and_demotes_low_efficacy_atom(db):
    """Repeated failures penalize confidence and demote low-efficacy atoms to pending_adjudication."""
    atom = MemoryAtom(
        id="fb-atom-2",
        project="Flightdeck",
        file_path="Sources/Network.swift",
        kind=MemoryKind.RULE,
        trigger_pattern="timeout",
        resolution="Ignore timeout errors",
        confidence=0.45,
    )
    db.save_atom(atom)

    # First failure
    db.record_feedback(atom_ids=["fb-atom-2"], outcome="failure")
    reloaded = db.get_atom("fb-atom-2")
    assert reloaded.failure_count == 1
    # 0.45 - 0.15 = 0.30 -> confidence < 0.35 triggers demotion!
    assert reloaded.confidence == 0.30
    assert reloaded.state == LifecycleState.PENDING_ADJUDICATION
    assert "Demoted due to low efficacy" in (reloaded.conflict_note or "")


def test_mcp_memory_feedback_tool(tmp_path):
    """Verifies the memory_feedback MCP tool."""
    db_file = tmp_path / "mcp_fb.db"
    test_db = ECSDatabase(db_file)
    atom = MemoryAtom(
        id="fb-atom-mcp",
        project="Flightdeck",
        file_path="Sources/Cache.swift",
        kind=MemoryKind.RULE,
        trigger_pattern="eviction",
        resolution="Use LRU cache with 100 item limit",
        confidence=0.80,
    )
    test_db.save_atom(atom)

    from ecs.server import create_mcp_server
    server = create_mcp_server(db_file)

    tool = server._tool_manager.get_tool("memory_feedback")
    assert tool is not None

    import json
    res_json = tool.fn(
        atom_ids="fb-atom-mcp",
        outcome="success",
        note="Passed all cache tests",
    )
    data = json.loads(res_json)
    assert data["status"] == "FEEDBACK_RECORDED"
    assert data["outcome"] == "success"
    assert data["updated_count"] == 1

    reloaded = test_db.get_atom("fb-atom-mcp")
    assert reloaded.success_count == 1
    assert reloaded.confidence == 0.85


def test_dream_audit_and_apply_handles_low_efficacy_atoms(db):
    """Dream consolidation identifies and quarantines low-efficacy atoms."""
    atom = MemoryAtom(
        id="fb-toxic-atom",
        project="Flightdeck",
        file_path="Sources/Legacy.swift",
        kind=MemoryKind.RULE,
        trigger_pattern="legacy init",
        resolution="Call private init directly",
        confidence=0.40,
        state=LifecycleState.ACTIVE,
    )
    atom.failure_count = 3
    atom.success_count = 0
    db.save_atom(atom)

    from ecs.dream import DreamEngine
    dreamer = DreamEngine(db)
    audit = dreamer.audit(project="Flightdeck")
    assert audit.low_efficacy_atoms == 1

    apply_res = dreamer.apply(project="Flightdeck")
    assert apply_res["demoted_low_efficacy"] == 1

    reloaded = db.get_atom("fb-toxic-atom")
    assert reloaded.state == LifecycleState.PENDING_ADJUDICATION
    assert "Quarantined by Dream Phase" in (reloaded.conflict_note or "")

