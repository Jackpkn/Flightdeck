"""SQLite-authoritative Bitemporal Causal Graph Storage with FTS5 Lexical Search."""

from __future__ import annotations
import json
import sqlite3
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Any

from .models import (
    AuthorityLevel,
    MemoryKind,
    LifecycleState,
    EdgeType,
    AnchorStatus,
    MemoryAnchor,
    MemoryAtom,
    MemoryEdge,
    BlastRadiusResult,
)


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _parse_dt(iso_str: str | None) -> datetime | None:
    if not iso_str:
        return None
    try:
        return datetime.fromisoformat(iso_str)
    except Exception:
        return None


class ECSDatabase:
    """Zero-bloat SQLite storage engine with FTS5 Porter stemming & recursive CTEs."""

    def __init__(self, db_path: str | Path | None = None):
        if db_path is None or str(db_path) == ":memory:":
            self.db_path = ":memory:"
        else:
            p = Path(db_path).expanduser().resolve()
            p.parent.mkdir(parents=True, exist_ok=True)
            self.db_path = str(p)

        self._conn = sqlite3.connect(self.db_path, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._init_pragmas()
        self._init_schema()

    def _init_pragmas(self) -> None:
        cur = self._conn.cursor()
        if self.db_path != ":memory:":
            cur.execute("PRAGMA journal_mode = WAL;")
            cur.execute("PRAGMA synchronous = NORMAL;")
        cur.execute("PRAGMA busy_timeout = 5000;")
        cur.execute("PRAGMA temp_store = MEMORY;")
        cur.execute("PRAGMA cache_size = -2000;")  # ~2MB max cache limit (RAM discipline)
        cur.execute("PRAGMA foreign_keys = ON;")
        self._conn.commit()

    def _init_schema(self) -> None:
        cur = self._conn.cursor()
        cur.executescript("""
            CREATE TABLE IF NOT EXISTS memory_atoms (
                id TEXT PRIMARY KEY,
                project TEXT NOT NULL,
                file_path TEXT NOT NULL,
                symbol TEXT,
                subject TEXT,
                predicate TEXT,
                object_value TEXT,
                kind TEXT NOT NULL,
                authority TEXT NOT NULL,
                trigger_pattern TEXT NOT NULL,
                failure_signature TEXT,
                resolution TEXT NOT NULL,
                state TEXT NOT NULL,
                anchor_status TEXT NOT NULL DEFAULT 'unverified',
                anchor_json TEXT,
                conflict_note TEXT,
                git_sha TEXT NOT NULL,
                file_hash TEXT,
                agent_id TEXT,
                session_id TEXT,
                source TEXT NOT NULL DEFAULT 'agent',
                verified_by TEXT NOT NULL DEFAULT 'compiler',
                occurrence_count INTEGER NOT NULL DEFAULT 1,
                evidence_refs TEXT,
                valid_from TEXT NOT NULL,
                valid_until TEXT,
                trial_until TEXT,
                recorded_at TEXT NOT NULL,
                invalidated_by TEXT,
                reward REAL NOT NULL,
                confidence REAL NOT NULL,
                label TEXT NOT NULL,
                view_set TEXT,
                hit_count INTEGER NOT NULL DEFAULT 0,
                success_count INTEGER NOT NULL DEFAULT 0,
                failure_count INTEGER NOT NULL DEFAULT 0,
                last_feedback_at TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
        """)

        # Safe migrations for pre-existing databases
        cur.execute("PRAGMA table_info(memory_atoms);")
        existing_cols = {row[1] for row in cur.fetchall()}
        for col_name in ["subject", "predicate", "object_value", "anchor_status", "anchor_json", "conflict_note", "source", "verified_by", "occurrence_count", "trial_until", "success_count", "failure_count", "last_feedback_at"]:
            if col_name not in existing_cols:
                try:
                    if col_name in ("occurrence_count",):
                        col_type = "INTEGER DEFAULT 1"
                    elif col_name in ("success_count", "failure_count"):
                        col_type = "INTEGER DEFAULT 0"
                    elif col_name == "anchor_status":
                        col_type = "TEXT DEFAULT 'unverified'"
                    elif col_name == "verified_by":
                        col_type = "TEXT DEFAULT 'compiler'"
                    else:
                        col_type = "TEXT"
                    cur.execute(f"ALTER TABLE memory_atoms ADD COLUMN {col_name} {col_type};")
                except sqlite3.OperationalError:
                    pass

        cur.executescript("""
            CREATE INDEX IF NOT EXISTS idx_atoms_project_path
                ON memory_atoms(project, file_path);

            CREATE INDEX IF NOT EXISTS idx_atoms_temporal
                ON memory_atoms(valid_from, valid_until, recorded_at);

            CREATE INDEX IF NOT EXISTS idx_atoms_state
                ON memory_atoms(state);

            CREATE INDEX IF NOT EXISTS idx_atoms_subject
                ON memory_atoms(project, subject);

            CREATE TABLE IF NOT EXISTS memory_edges (
                id TEXT PRIMARY KEY,
                from_atom_id TEXT NOT NULL,
                to_atom_id TEXT NOT NULL,
                edge_type TEXT NOT NULL,
                valid_from TEXT NOT NULL,
                valid_until TEXT,
                recorded_at TEXT NOT NULL,
                invalidated_by TEXT,
                FOREIGN KEY (from_atom_id) REFERENCES memory_atoms(id) ON DELETE CASCADE,
                FOREIGN KEY (to_atom_id) REFERENCES memory_atoms(id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS idx_edges_from
                ON memory_edges(from_atom_id);

            CREATE INDEX IF NOT EXISTS idx_edges_to
                ON memory_edges(to_atom_id);

            CREATE INDEX IF NOT EXISTS idx_edges_temporal
                ON memory_edges(valid_from, valid_until);

            CREATE TABLE IF NOT EXISTS recall_observations (
                id TEXT PRIMARY KEY,
                atom_id TEXT NOT NULL,
                session_id TEXT,
                agent_id TEXT,
                outcome TEXT NOT NULL,
                recorded_at TEXT NOT NULL,
                FOREIGN KEY (atom_id) REFERENCES memory_atoms(id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS idx_observations_atom
                ON recall_observations(atom_id);

            -- FTS5 Full Text Index with Porter Stemming (Legendary-MCP pattern)
            CREATE VIRTUAL TABLE IF NOT EXISTS memory_atoms_fts USING fts5(
                id UNINDEXED,
                trigger_pattern,
                resolution,
                symbol,
                file_path,
                subject,
                tokenize='porter'
            );

            -- Triggers to maintain FTS5 index in sync
            CREATE TRIGGER IF NOT EXISTS trg_atoms_insert AFTER INSERT ON memory_atoms BEGIN
                INSERT INTO memory_atoms_fts(id, trigger_pattern, resolution, symbol, file_path, subject)
                VALUES (new.id, new.trigger_pattern, new.resolution, coalesce(new.symbol, ''), new.file_path, coalesce(new.subject, ''));
            END;

            CREATE TRIGGER IF NOT EXISTS trg_atoms_update AFTER UPDATE ON memory_atoms BEGIN
                DELETE FROM memory_atoms_fts WHERE id = old.id;
                INSERT INTO memory_atoms_fts(id, trigger_pattern, resolution, symbol, file_path, subject)
                VALUES (new.id, new.trigger_pattern, new.resolution, coalesce(new.symbol, ''), new.file_path, coalesce(new.subject, ''));
            END;

            CREATE TRIGGER IF NOT EXISTS trg_atoms_delete AFTER DELETE ON memory_atoms BEGIN
                DELETE FROM memory_atoms_fts WHERE id = old.id;
            END;
        """)
        self._conn.commit()

    def close(self) -> None:
        self._conn.close()

    # MARK: - Atoms CRUD

    def save_atom(self, atom: MemoryAtom) -> None:
        cur = self._conn.cursor()
        now = _now_iso()
        anchor_json = json.dumps(atom.anchor.to_dict()) if atom.anchor else None
        cur.execute("""
            INSERT INTO memory_atoms (
                id, project, file_path, symbol, subject, predicate, object_value,
                kind, authority, trigger_pattern, failure_signature, resolution, state,
                anchor_status, anchor_json, conflict_note,
                git_sha, file_hash, agent_id, session_id, source, verified_by, occurrence_count, evidence_refs,
                valid_from, valid_until, trial_until, recorded_at, invalidated_by,
                reward, confidence, label, view_set, hit_count,
                success_count, failure_count, last_feedback_at,
                created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                project=excluded.project,
                file_path=excluded.file_path,
                symbol=excluded.symbol,
                subject=excluded.subject,
                predicate=excluded.predicate,
                object_value=excluded.object_value,
                kind=excluded.kind,
                authority=excluded.authority,
                trigger_pattern=excluded.trigger_pattern,
                failure_signature=excluded.failure_signature,
                resolution=excluded.resolution,
                state=excluded.state,
                anchor_status=excluded.anchor_status,
                anchor_json=excluded.anchor_json,
                conflict_note=excluded.conflict_note,
                git_sha=excluded.git_sha,
                file_hash=excluded.file_hash,
                agent_id=excluded.agent_id,
                session_id=excluded.session_id,
                source=excluded.source,
                verified_by=excluded.verified_by,
                occurrence_count=excluded.occurrence_count,
                evidence_refs=excluded.evidence_refs,
                valid_from=excluded.valid_from,
                valid_until=excluded.valid_until,
                trial_until=excluded.trial_until,
                invalidated_by=excluded.invalidated_by,
                reward=excluded.reward,
                confidence=excluded.confidence,
                label=excluded.label,
                view_set=excluded.view_set,
                hit_count=excluded.hit_count,
                success_count=excluded.success_count,
                failure_count=excluded.failure_count,
                last_feedback_at=excluded.last_feedback_at,
                updated_at=?
        """, (
            atom.id,
            atom.project,
            atom.file_path,
            atom.symbol,
            atom.subject,
            atom.predicate,
            atom.object_value,
            atom.kind.value,
            atom.authority.value,
            atom.trigger_pattern,
            atom.failure_signature,
            atom.resolution,
            atom.state.value,
            atom.anchor_status.value,
            anchor_json,
            atom.conflict_note,
            atom.git_sha,
            atom.file_hash,
            atom.agent_id,
            atom.session_id,
            atom.source,
            atom.verified_by,
            atom.occurrence_count,
            json.dumps(atom.evidence_refs),
            atom.valid_from.isoformat(),
            atom.valid_until.isoformat() if atom.valid_until else None,
            atom.trial_until.isoformat() if atom.trial_until else None,
            atom.recorded_at.isoformat(),
            atom.invalidated_by,
            atom.reward,
            atom.confidence,
            atom.label,
            json.dumps(atom.view_set),
            atom.hit_count,
            atom.success_count,
            atom.failure_count,
            atom.last_feedback_at.isoformat() if atom.last_feedback_at else None,
            atom.created_at.isoformat(),
            atom.updated_at.isoformat(),
            now,
        ))
        self._conn.commit()

    def get_atom(self, atom_id: str) -> MemoryAtom | None:
        cur = self._conn.cursor()
        cur.execute("SELECT * FROM memory_atoms WHERE id = ?", (atom_id,))
        row = cur.fetchone()
        if not row:
            return None
        return self._row_to_atom(row)

    def fetch_atoms(
        self,
        project: str | None = None,
        file_path: str | None = None,
        symbol: str | None = None,
        subject: str | None = None,
        state: LifecycleState | None = None,
        min_confidence: float = 0.0,
        active_only: bool = True,
    ) -> list[MemoryAtom]:
        query = "SELECT * FROM memory_atoms WHERE 1=1"
        params: list[Any] = []

        if project:
            query += " AND project = ?"
            params.append(project)
        if file_path:
            query += " AND file_path = ?"
            params.append(file_path)
        if symbol:
            query += " AND symbol = ?"
            params.append(symbol)
        if subject:
            query += " AND subject = ?"
            params.append(subject)
        if state:
            query += " AND state = ?"
            params.append(state.value)
        elif active_only:
            query += " AND state IN ('active', 'conflicted') AND (valid_until IS NULL OR valid_until > datetime('now'))"

        if min_confidence > 0.0:
            query += " AND confidence >= ?"
            params.append(min_confidence)

        query += " ORDER BY confidence DESC, updated_at DESC"

        cur = self._conn.cursor()
        cur.execute(query, params)
        return [self._row_to_atom(row) for row in cur.fetchall()]

    def fetch_pending_adjudication_count(self, project: str | None = None) -> int:
        cur = self._conn.cursor()
        if project:
            cur.execute("SELECT COUNT(*) FROM memory_atoms WHERE state = 'pending_adjudication' AND project = ?", (project,))
        else:
            cur.execute("SELECT COUNT(*) FROM memory_atoms WHERE state = 'pending_adjudication'")
        return cur.fetchone()[0]

    def search_fts(
        self,
        query_text: str,
        project: str,
        active_files: list[str] | None = None,
        limit: int = 20,
    ) -> list[tuple[MemoryAtom, float]]:
        """
        FTS5 ranking: BM25 score + file overlap bonus - staleness penalty (Legendary-MCP pattern).
        """
        # Clean query for FTS5 syntax
        clean_terms = [t for t in query_text.replace("'", " ").replace('"', " ").split() if len(t) > 1]
        if not clean_terms:
            return []
        match_expr = " ".join(clean_terms)

        sql = """
            SELECT a.*, bm25(memory_atoms_fts) as rank
            FROM memory_atoms_fts f
            JOIN memory_atoms a ON f.id = a.id
            WHERE memory_atoms_fts MATCH ?
              AND a.project = ?
              AND a.state IN ('active', 'stale', 'conflicted')
              AND a.anchor_status != 'contradicted'
            ORDER BY rank ASC
            LIMIT ?
        """
        cur = self._conn.cursor()
        is_fallback = False
        try:
            cur.execute(sql, (match_expr, project, limit))
            rows = cur.fetchall()
            # If conjunctive match returned nothing, fallback to disjunctive OR with term coverage check
            if not rows and len(clean_terms) > 1:
                is_fallback = True
                cur.execute(sql, (" OR ".join(clean_terms), project, limit))
                rows = cur.fetchall()
        except sqlite3.OperationalError:
            return []

        active_set = set(f.strip().lstrip("./") for f in (active_files or []))
        scored: list[tuple[MemoryAtom, float]] = []

        for r in rows:
            atom = self._row_to_atom(r)

            # Prevent false positive poisoning: for disjunctive fallback on multi-term queries,
            # require meaningful content term coverage (excluding common stopwords).
            if is_fallback and len(clean_terms) >= 3:
                stopwords = {"in", "on", "at", "to", "for", "the", "a", "an", "is", "of", "and", "or", "by", "with", "from"}
                content_terms = [t.lower() for t in clean_terms if t.lower() not in stopwords]
                atom_corpus = f"{atom.trigger_pattern} {atom.failure_signature or ''} {atom.resolution} {atom.symbol or ''} {atom.file_path}".lower()
                matched_count = sum(1 for term in content_terms if term in atom_corpus)
                if len(content_terms) >= 2 and (matched_count < 2 or (matched_count / len(content_terms)) < 0.40):
                    continue

            # In SQLite FTS5, bm25() returns negative numbers where more negative = better match.
            # Base match credit (0.50) ensures small corpora (where N is small and FTS5 clamps IDF)
            # still register lexical matches correctly, scaling with BM25:
            abs_bm25 = abs(r["rank"])
            bm25_norm = abs_bm25 / (1.0 + abs_bm25)
            base_score = 0.50 + 0.50 * bm25_norm

            # Overlap with files being edited (bonus)
            atom_path = atom.file_path.strip().lstrip("./")
            if atom_path in active_set:
                base_score += 0.40
            elif any(atom_path.endswith(f) for f in active_set):
                base_score += 0.20

            # Staleness penalty
            if atom.anchor_status == AnchorStatus.STALE or atom.state == LifecycleState.STALE:
                base_score = max(0.05, base_score - 0.35)

            # Authority multiplier
            base_score *= atom.authority.trust_score

            scored.append((atom, base_score))

        scored.sort(key=lambda x: x[1], reverse=True)
        return scored

    def invalidate_atom(self, atom_id: str, invalidated_by: str | None = None) -> None:
        """Closes valid_until and explicitly records invalidation chain."""
        now = _now_iso()
        cur = self._conn.cursor()
        cur.execute("""
            UPDATE memory_atoms
            SET valid_until = ?,
                invalidated_by = ?,
                state = 'superseded',
                updated_at = ?
            WHERE id = ?
        """, (now, invalidated_by, now, atom_id))
        self._conn.commit()

    def record_hit(self, atom_id: str) -> None:
        now = _now_iso()
        cur = self._conn.cursor()
        cur.execute("""
            UPDATE memory_atoms
            SET hit_count = hit_count + 1, updated_at = ?
            WHERE id = ?
        """, (now, atom_id))
        self._conn.commit()

    def record_feedback(
        self,
        atom_ids: list[str],
        outcome: str,
        error_signature: str = "",
        note: str = "",
    ) -> dict[str, Any]:
        """
        Records the execution outcome of an agent turn for the retrieved memory atoms.
        Adjusts confidence, updates success/failure counters, and demotes failing atoms.
        """
        clean_outcome = outcome.strip().lower()
        is_success = clean_outcome in ("success", "pass", "passed", "true", "1")
        now = datetime.now(timezone.utc)

        updated = []
        demoted = []

        cur = self._conn.cursor()
        for atom_id in atom_ids:
            cur.execute("SELECT * FROM memory_atoms WHERE id = ?", (atom_id,))
            row = cur.fetchone()
            if not row:
                continue
            atom = self._row_to_atom(row)
            if is_success:
                atom.success_count += 1
                atom.confidence = min(1.0, round(atom.confidence + 0.05, 3))
            else:
                atom.failure_count += 1
                atom.confidence = max(0.1, round(atom.confidence - 0.15, 3))
                # If failure is severe or repeated without success, demote to pending adjudication
                if atom.confidence < 0.35 or (atom.failure_count >= 3 and atom.success_count == 0):
                    atom.state = LifecycleState.PENDING_ADJUDICATION
                    msg = f"Demoted due to low efficacy: {atom.failure_count} failure(s), confidence {atom.confidence}"
                    if error_signature:
                        msg += f" (Error: {error_signature[:80]})"
                    atom.conflict_note = f"{atom.conflict_note}; {msg}" if atom.conflict_note else msg
                    demoted.append(atom.id)

            atom.last_feedback_at = now
            atom.updated_at = now
            self.save_atom(atom)
            updated.append({
                "id": atom.id,
                "confidence": atom.confidence,
                "efficacy_score": round(atom.efficacy_score, 3),
                "success_count": atom.success_count,
                "failure_count": atom.failure_count,
                "state": atom.state.value,
            })

        self._conn.commit()
        return {
            "status": "FEEDBACK_RECORDED",
            "outcome": "success" if is_success else "failure",
            "updated_count": len(updated),
            "updated_atoms": updated,
            "demoted_count": len(demoted),
            "demoted_atoms": demoted,
        }

    # MARK: - Edges CRUD

    def save_edge(self, edge: MemoryEdge) -> None:
        cur = self._conn.cursor()
        cur.execute("""
            INSERT INTO memory_edges (
                id, from_atom_id, to_atom_id, edge_type,
                valid_from, valid_until, recorded_at, invalidated_by
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                valid_until=excluded.valid_until,
                invalidated_by=excluded.invalidated_by
        """, (
            edge.id,
            edge.from_atom_id,
            edge.to_atom_id,
            edge.edge_type.value,
            edge.valid_from.isoformat(),
            edge.valid_until.isoformat() if edge.valid_until else None,
            edge.recorded_at.isoformat(),
            edge.invalidated_by,
        ))
        self._conn.commit()

    def fetch_edges(
        self,
        from_id: str | None = None,
        to_id: str | None = None,
        edge_type: EdgeType | None = None,
        active_only: bool = True,
    ) -> list[MemoryEdge]:
        query = "SELECT * FROM memory_edges WHERE 1=1"
        params: list[Any] = []

        if from_id:
            query += " AND from_atom_id = ?"
            params.append(from_id)
        if to_id:
            query += " AND to_atom_id = ?"
            params.append(to_id)
        if edge_type:
            query += " AND edge_type = ?"
            params.append(edge_type.value)
        if active_only:
            query += " AND (valid_until IS NULL OR valid_until > datetime('now'))"

        cur = self._conn.cursor()
        cur.execute(query, params)
        return [self._row_to_edge(row) for row in cur.fetchall()]

    def record_dead_end(
        self,
        parent_id: str | None,
        file_path: str,
        attempted_fix: str,
        failure_signature: str = "",
        trigger_pattern: str = "",
        symbol: str | None = None,
        project: str = "default",
        authority: AuthorityLevel = AuthorityLevel.L2,
    ) -> tuple[MemoryAtom, MemoryEdge | None]:
        """
        Records a falsified hypothesis (dead end) and links it to parent atom via LEADS_TO_DEAD_END edge.
        """
        dead_end_atom = MemoryAtom(
            project=project,
            file_path=file_path,
            symbol=symbol,
            kind=MemoryKind.DEAD_END,
            authority=authority,
            trigger_pattern=trigger_pattern,
            failure_signature=failure_signature,
            resolution=attempted_fix,
            state=LifecycleState.ACTIVE,
        )
        self.save_atom(dead_end_atom)
        edge = None
        if parent_id and self.get_atom(parent_id):
            edge = MemoryEdge(
                from_atom_id=parent_id,
                to_atom_id=dead_end_atom.id,
                edge_type=EdgeType.LEADS_TO_DEAD_END,
            )
            self.save_edge(edge)
        return dead_end_atom, edge

    def fetch_dead_ends(self, parent_id: str) -> list[MemoryAtom]:
        """Fetches active dead-end atoms linked from parent atom via LEADS_TO_DEAD_END."""
        edges = self.fetch_edges(from_id=parent_id, edge_type=EdgeType.LEADS_TO_DEAD_END, active_only=True)
        dead_ends: list[MemoryAtom] = []
        for edge in edges:
            atom = self.get_atom(edge.to_atom_id)
            if atom and atom.state == LifecycleState.ACTIVE:
                dead_ends.append(atom)
        return dead_ends

    # MARK: - Recursive CTE Blast Radius

    def compute_blast_radius(
        self,
        atom_id: str,
        max_depth: int = 3,
        limit: int = 100,
    ) -> BlastRadiusResult:
        """
        Bidirectional causal impact analysis via recursive CTE with deterministic tie-breaking.
        Traverses outgoing dependencies/causes and incoming solutions (fix -> problem).
        Returns BlastRadiusResult containing nodes, truncation flag, and total affected estimate.
        """
        sql = """
        WITH RECURSIVE blast(id, depth) AS (
            SELECT id, 0 FROM memory_atoms WHERE id = ?
            UNION
            -- Outgoing forward causal / dependency / solution / dead-end propagation
            SELECT e.to_atom_id, blast.depth + 1
            FROM memory_edges e JOIN blast ON e.from_atom_id = blast.id
            WHERE e.edge_type IN ('DEPENDS_ON', 'CAUSES', 'SOLVES', 'LEADS_TO_DEAD_END')
              AND (e.valid_until IS NULL OR e.valid_until > datetime('now'))
              AND blast.depth < ?
            UNION
            -- Reverse resolution & causation traversal:
            -- When seeded with a problem/trap, find the fix that SOLVES it (fix -> problem).
            -- When seeded with an effect, find the root cause (cause -> effect).
            SELECT e.from_atom_id, blast.depth + 1
            FROM memory_edges e JOIN blast ON e.to_atom_id = blast.id
            WHERE e.edge_type IN ('SOLVES', 'CAUSES')
              AND (e.valid_until IS NULL OR e.valid_until > datetime('now'))
              AND blast.depth < ?
        )
        -- Order deterministically: min_depth ASC, id ASC to eliminate non-deterministic ties at depth boundaries
        SELECT id, MIN(depth) as min_depth
        FROM blast
        WHERE id != ?
        GROUP BY id
        ORDER BY min_depth ASC, id ASC;
        """
        cur = self._conn.cursor()
        cur.execute(sql, (atom_id, max_depth, max_depth, atom_id))
        all_rows = cur.fetchall()
        total_estimate = len(all_rows)
        truncated = total_estimate > limit
        selected_nodes = [row["id"] for row in all_rows[:limit]]
        return BlastRadiusResult(
            nodes=selected_nodes,
            truncated=truncated,
            total_estimate=total_estimate,
        )

    # MARK: - Stats & Compaction

    def get_stats(self, project: str | None = None) -> dict[str, Any]:
        cur = self._conn.cursor()
        clause = "WHERE project = ?" if project else ""
        params = (project,) if project else ()

        cur.execute(f"SELECT COUNT(*) FROM memory_atoms {clause}", params)
        total_atoms = cur.fetchone()[0]

        cur.execute(f"SELECT COUNT(*) FROM memory_atoms {clause} {'AND' if project else 'WHERE'} state = 'active'", params)
        active_atoms = cur.fetchone()[0]

        cur.execute(f"SELECT COUNT(*) FROM memory_atoms {clause} {'AND' if project else 'WHERE'} state = 'stale'", params)
        stale_atoms = cur.fetchone()[0]

        cur.execute(f"SELECT COUNT(*) FROM memory_atoms {clause} {'AND' if project else 'WHERE'} state = 'superseded'", params)
        superseded_atoms = cur.fetchone()[0]

        cur.execute(f"SELECT COUNT(*) FROM memory_atoms {clause} {'AND' if project else 'WHERE'} state = 'quarantined'", params)
        quarantined_atoms = cur.fetchone()[0]

        cur.execute(f"SELECT COUNT(*) FROM memory_atoms {clause} {'AND' if project else 'WHERE'} state = 'conflicted'", params)
        conflicted_atoms = cur.fetchone()[0]

        cur.execute("SELECT COUNT(*) FROM memory_edges")
        total_edges = cur.fetchone()[0]

        return {
            "total_atoms": total_atoms,
            "active_atoms": active_atoms,
            "stale_atoms": stale_atoms,
            "superseded_atoms": superseded_atoms,
            "quarantined_atoms": quarantined_atoms,
            "conflicted_atoms": conflicted_atoms,
            "total_edges": total_edges,
            "database_path": self.db_path,
        }

    def compact_tombstones(self, retention_days: int = 7, max_conflict_age_days: int = 90, dry_run: bool = True) -> dict[str, int]:
        """Prunes tombstoned atoms past retention floor, and archives unresolved conflicts older than 90 days."""
        cutoff = (datetime.now(timezone.utc) - timedelta(days=retention_days)).isoformat()
        conflict_cutoff = (datetime.now(timezone.utc) - timedelta(days=max_conflict_age_days)).isoformat()
        cur = self._conn.cursor()

        cur.execute("""
            SELECT COUNT(*) FROM memory_atoms
            WHERE state = 'conflicted'
              AND updated_at < ?
        """, (conflict_cutoff,))
        archived_conflicts = cur.fetchone()[0]

        cur.execute("""
            SELECT COUNT(*) FROM memory_atoms
            WHERE state IN ('stale', 'superseded', 'obsolete')
              AND updated_at < ?
        """, (cutoff,))
        eligible = cur.fetchone()[0]

        deleted = 0
        conflicts_archived = 0
        if not dry_run:
            if archived_conflicts > 0:
                now = _now_iso()
                cur.execute("""
                    UPDATE memory_atoms
                    SET state = 'obsolete',
                        conflict_note = COALESCE(conflict_note, '') || ' [Archived: unresolved after 90 days]',
                        updated_at = ?
                    WHERE state = 'conflicted'
                      AND updated_at < ?
                """, (now, conflict_cutoff))
                conflicts_archived = archived_conflicts

            if eligible > 0:
                cur.execute("""
                    DELETE FROM memory_atoms
                    WHERE state IN ('stale', 'superseded', 'obsolete')
                      AND updated_at < ?
                """, (cutoff,))
                deleted = eligible
            self._conn.commit()

        return {"eligible": eligible, "deleted": deleted, "archived_conflicts": archived_conflicts}

    # MARK: - Row Mappers

    def _row_to_atom(self, row: sqlite3.Row) -> MemoryAtom:
        evidence = json.loads(row["evidence_refs"]) if row["evidence_refs"] else []
        view_set = json.loads(row["view_set"]) if row["view_set"] else ["full"]
        anchor_dict = json.loads(row["anchor_json"]) if "anchor_json" in row.keys() and row["anchor_json"] else None
        anchor = MemoryAnchor.from_dict(anchor_dict) if anchor_dict else None

        anchor_status = AnchorStatus.UNVERIFIED
        if "anchor_status" in row.keys() and row["anchor_status"]:
            try:
                anchor_status = AnchorStatus(row["anchor_status"])
            except ValueError:
                pass

        return MemoryAtom(
            id=row["id"],
            project=row["project"],
            file_path=row["file_path"],
            symbol=row["symbol"],
            subject=row["subject"] if "subject" in row.keys() else None,
            predicate=row["predicate"] if "predicate" in row.keys() else None,
            object_value=row["object_value"] if "object_value" in row.keys() else None,
            kind=MemoryKind(row["kind"]),
            authority=AuthorityLevel(row["authority"]),
            trigger_pattern=row["trigger_pattern"],
            failure_signature=row["failure_signature"],
            resolution=row["resolution"],
            state=LifecycleState(row["state"]),
            anchor=anchor,
            anchor_status=anchor_status,
            conflict_note=row["conflict_note"] if "conflict_note" in row.keys() else None,
            git_sha=row["git_sha"],
            file_hash=row["file_hash"],
            agent_id=row["agent_id"],
            session_id=row["session_id"],
            source=row["source"] if "source" in row.keys() and row["source"] else "agent",
            verified_by=row["verified_by"] if "verified_by" in row.keys() and row["verified_by"] else "compiler",
            occurrence_count=row["occurrence_count"] if "occurrence_count" in row.keys() and row["occurrence_count"] is not None else 1,
            evidence_refs=evidence,
            valid_from=_parse_dt(row["valid_from"]) or datetime.now(timezone.utc),
            valid_until=_parse_dt(row["valid_until"]),
            trial_until=_parse_dt(row["trial_until"]) if "trial_until" in row.keys() else None,
            recorded_at=_parse_dt(row["recorded_at"]) or datetime.now(timezone.utc),
            invalidated_by=row["invalidated_by"],
            reward=row["reward"],
            confidence=row["confidence"],
            label=row["label"],
            view_set=view_set,
            hit_count=row["hit_count"],
            success_count=row["success_count"] if "success_count" in row.keys() and row["success_count"] is not None else 0,
            failure_count=row["failure_count"] if "failure_count" in row.keys() and row["failure_count"] is not None else 0,
            last_feedback_at=_parse_dt(row["last_feedback_at"]) if "last_feedback_at" in row.keys() else None,
            created_at=_parse_dt(row["created_at"]) or datetime.now(timezone.utc),
            updated_at=_parse_dt(row["updated_at"]) or datetime.now(timezone.utc),
        )

    def _row_to_edge(self, row: sqlite3.Row) -> MemoryEdge:
        return MemoryEdge(
            id=row["id"],
            from_atom_id=row["from_atom_id"],
            to_atom_id=row["to_atom_id"],
            edge_type=EdgeType(row["edge_type"]),
            valid_from=_parse_dt(row["valid_from"]) or datetime.now(timezone.utc),
            valid_until=_parse_dt(row["valid_until"]),
            recorded_at=_parse_dt(row["recorded_at"]) or datetime.now(timezone.utc),
            invalidated_by=row["invalidated_by"],
        )
