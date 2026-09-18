"""Git Hash-Anchored Symbol Verification Probe (Context Fabric & Memory-MCP pattern)."""

from __future__ import annotations
from functools import lru_cache
import hashlib
from pathlib import Path
import subprocess
from typing import NamedTuple

from .models import MemoryAnchor, AnchorStatus, MemoryAtom, LifecycleState, EdgeType, MemoryEdge
from .db import ECSDatabase


class AnchorVerificationResult(NamedTuple):
    status: AnchorStatus
    current_hash: str
    symbol_found: bool
    reason: str


class DriftReport(NamedTuple):
    total_anchors: int
    verified_count: int
    stale_count: int
    contradicted_count: int
    missing_source_count: int
    drift_fraction: float  # (stale + contradicted) / total
    severity: str          # LOW (<10%), MED (10-30%), HIGH (>30%)


class GitProbe:
    """Hash-anchored symbol verifier reading immutable committed git blobs."""

    @staticmethod
    def sha256_bytes(data: bytes) -> str:
        return hashlib.sha256(data).hexdigest()

    @staticmethod
    def sha256_str(text: str) -> str:
        return hashlib.sha256(text.encode("utf-8")).hexdigest()

    @staticmethod
    @lru_cache(maxsize=512)
    def _cached_committed_blob(file_path: str, repo_root_str: str, commit: str) -> bytes | None:
        try:
            res = subprocess.run(
                ["git", "-C", repo_root_str, "show", f"{commit}:{file_path}"],
                capture_output=True,
                check=False,
            )
            if res.returncode == 0:
                return res.stdout
            return None
        except Exception:
            return None

    @classmethod
    def committed_blob(cls, file_path: str, repo_root: Path | str, commit: str = "HEAD") -> bytes | None:
        """Reads the committed file blob directly from git object store with LRU cache."""
        clean_path = file_path.strip().lstrip("./")
        return cls._cached_committed_blob(clean_path, str(repo_root), commit)

    @classmethod
    @lru_cache(maxsize=32)
    def _cached_current_commit_sha(cls, repo_root_str: str) -> str:
        try:
            res = subprocess.run(
                ["git", "-C", repo_root_str, "rev-parse", "HEAD"],
                capture_output=True,
                text=True,
                check=False,
            )
            if res.returncode == 0:
                s = res.stdout.strip()
                return s if s else "HEAD"
            return "HEAD"
        except Exception:
            return "HEAD"

    @classmethod
    def current_commit_sha(cls, repo_root: Path | str) -> str:
        return cls._cached_current_commit_sha(str(repo_root))

    @classmethod
    def clear_cache(cls) -> None:
        cls._cached_committed_blob.cache_clear()
        cls._cached_current_commit_sha.cache_clear()

    @classmethod
    def verify_anchor(
        cls,
        anchor: MemoryAnchor,
        repo_root: Path | str,
        commit: str = "HEAD",
    ) -> AnchorVerificationResult:
        """
        Verifies anchor against committed git blob:
        - VERIFIED: blob SHA-256 matches anchor.content_hash exactly
        - STALE: blob changed, but referenced symbol persists (inject with staleness warning)
        - CONTRADICTED: blob changed and referenced symbol is gone (block from being injected as fact)
        - MISSING_SOURCE: file deleted from repository
        """
        root = Path(repo_root)
        clean_path = anchor.file_path.strip().lstrip("./")

        # 1. Check if file exists in committed tree
        blob = cls.committed_blob(clean_path, root, commit=commit)
        if blob is None:
            # Check if exists on filesystem as fallback
            fs_path = root / clean_path
            if not fs_path.is_file():
                return AnchorVerificationResult(
                    status=AnchorStatus.MISSING_SOURCE,
                    current_hash="",
                    symbol_found=False,
                    reason=f"File {clean_path} deleted from git repository",
                )
            try:
                blob = fs_path.read_bytes()
            except Exception:
                return AnchorVerificationResult(
                    status=AnchorStatus.MISSING_SOURCE,
                    current_hash="",
                    symbol_found=False,
                    reason=f"Could not read {clean_path}",
                )

        current_hash = cls.sha256_bytes(blob)

        # 2. Exact match
        if anchor.content_hash and current_hash == anchor.content_hash:
            return AnchorVerificationResult(
                status=AnchorStatus.VERIFIED,
                current_hash=current_hash,
                symbol_found=True,
                reason="Committed blob matches anchor hash exactly",
            )

        # 3. Content hash changed — verify symbol presence in committed blob
        text_content = blob.decode("utf-8", errors="ignore")
        symbol_present = True
        if anchor.symbol_name:
            symbol_present = anchor.symbol_name in text_content

        if not symbol_present:
            # The symbol this memory referenced is gone -> CONTRADICTED
            return AnchorVerificationResult(
                status=AnchorStatus.CONTRADICTED,
                current_hash=current_hash,
                symbol_found=False,
                reason=f"Symbol '{anchor.symbol_name}' no longer exists in committed blob",
            )

        # Region changed, but symbol persists -> STALE
        return AnchorVerificationResult(
            status=AnchorStatus.STALE,
            current_hash=current_hash,
            symbol_found=True,
            reason="Committed blob changed since memory was written, but symbol persists",
        )

    @classmethod
    def verify_atom_on_demand(cls, atom: MemoryAtom, repo_root: Path | str) -> MemoryAtom:
        """Runs on-demand verification during retrieval (Context Fabric pattern)."""
        if not atom.anchor:
            # If no anchor stored, create a synthesized one from file_path and symbol
            blob = cls.committed_blob(atom.file_path, repo_root)
            current_hash = cls.sha256_bytes(blob) if blob else ""
            atom.anchor = MemoryAnchor(
                file_path=atom.file_path,
                symbol_name=atom.symbol,
                content_hash=atom.file_hash or current_hash,
                commit_sha=atom.git_sha,
            )

        res = cls.verify_anchor(atom.anchor, repo_root)
        atom.anchor_status = res.status
        if res.status == AnchorStatus.CONTRADICTED:
            atom.state = LifecycleState.STALE  # Blocked from being served as active fact
        elif res.status == AnchorStatus.MISSING_SOURCE:
            atom.state = LifecycleState.STALE
        return atom

    @classmethod
    def compute_drift_report(cls, atoms: list[MemoryAtom], repo_root: Path | str) -> DriftReport:
        """Computes drift report across a set of atoms."""
        verified = 0
        stale = 0
        contradicted = 0
        missing = 0

        for atom in atoms:
            if not atom.anchor:
                continue
            res = cls.verify_anchor(atom.anchor, repo_root)
            if res.status == AnchorStatus.VERIFIED:
                verified += 1
            elif res.status == AnchorStatus.STALE:
                stale += 1
            elif res.status == AnchorStatus.CONTRADICTED:
                contradicted += 1
            elif res.status == AnchorStatus.MISSING_SOURCE:
                missing += 1

        total = len(atoms)
        if total == 0:
            return DriftReport(0, 0, 0, 0, 0, 0.0, "LOW")

        drift = (stale + contradicted + missing) / total
        severity = "LOW"
        if drift >= 0.30:
            severity = "HIGH"
        elif drift >= 0.10:
            severity = "MED"

        return DriftReport(
            total_anchors=total,
            verified_count=verified,
            stale_count=stale,
            contradicted_count=contradicted,
            missing_source_count=missing,
            drift_fraction=round(drift, 3),
            severity=severity,
        )

    @classmethod
    def reverify_stale_dependents(
        cls,
        db: ECSDatabase,
        repo_root: Path | str,
        project: str | None = None,
    ) -> tuple[int, int]:
        """
        Re-verifies stale dependents whose premise was superseded.
        If the dependent's target symbol and trigger pattern still hold against the committed git blob,
        and its invalidated premise has an active replacement, it un-stales the dependent,
        rewires the DEPENDS_ON edge to the active replacement premise, and restores active status.
        """
        atoms = db.fetch_atoms(project=project, active_only=False)
        stale_dependents = [
            a for a in atoms
            if a.state == LifecycleState.STALE or a.anchor_status == AnchorStatus.STALE
        ]
        recovered = 0
        remained = 0

        for a in stale_dependents:
            blob = cls.committed_blob(a.file_path, repo_root)
            if not blob:
                remained += 1
                continue
            text = blob.decode("utf-8", errors="replace")
            symbol_valid = not a.symbol or a.symbol in text
            trigger_valid = a.trigger_pattern in text or any(term in text for term in a.trigger_pattern.split()[:2])

            if symbol_valid and trigger_valid:
                # Check if dependency can be rewired
                edges = db.fetch_edges(from_id=a.id, edge_type=EdgeType.DEPENDS_ON)
                for edge in edges:
                    old_premise = db.get_atom(edge.to_atom_id)
                    if old_premise and old_premise.invalidated_by:
                        new_premise = db.get_atom(old_premise.invalidated_by)
                        if new_premise and new_premise.state == LifecycleState.ACTIVE:
                            db.save_edge(MemoryEdge(
                                from_atom_id=a.id,
                                to_atom_id=new_premise.id,
                                edge_type=EdgeType.DEPENDS_ON,
                            ))
                a.state = LifecycleState.ACTIVE
                a.anchor_status = AnchorStatus.VERIFIED
                a.conflict_note = "✓ Re-verified against committed code state."
                db.save_atom(a)
                recovered += 1
            else:
                remained += 1

        return recovered, remained

