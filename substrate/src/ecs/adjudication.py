"""Write-Side Adjudication & Contradiction Engine (CUPMem Protocol & Two-Stage Adjudication)."""

from __future__ import annotations
from datetime import datetime, timezone
import re
from typing import Sequence

from .models import (
    AuthorityLevel,
    LifecycleState,
    EdgeType,
    AdjudicationDecision,
    ContradictionKind,
    MemoryAtom,
    MemoryEdge,
    VerifierSignal,
)
from .db import ECSDatabase


class AdjudicationEngine:
    """Governs write-side entry into the Bitemporal Causal Graph with explicit contradiction detection."""

    def __init__(self, db: ECSDatabase):
        self.db = db

    CODE_IDENTIFIER_PATTERN = re.compile(
        r'(\.[a-zA-Z_][a-zA-Z0-9_]*|`[^`]+`|[a-zA-Z_][a-zA-Z0-9_]*\([^\)]*\)|--[a-z0-9-]+|[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+|\b[a-zA-Z0-9_]+\.[a-zA-Z0-9_]+\b|\b[A-Z][a-zA-Z0-9]+(?:\.[A-Z][a-zA-Z0-9]+)*\b)'
    )

    def verify_candidate(self, atom: MemoryAtom) -> VerifierSignal:
        """MemGuard-style verification pass assessing trajectory validity & authority."""
        # 1. External L4 documents are always quarantined
        if atom.authority == AuthorityLevel.L4:
            atom.verified_by = "untrusted_external"
            return VerifierSignal(
                reward=0.3,
                confidence=0.3,
                label="quarantined",
                view_set=["risk"],
            )

        # 2. Ground truth L0 / L1 compiler exit codes & filesystem state
        if atom.authority in (AuthorityLevel.L0, AuthorityLevel.L1):
            if atom.authority == AuthorityLevel.L0:
                atom.verified_by = "filesystem"
            else:
                atom.verified_by = "compiler"
            return VerifierSignal(
                reward=1.0,
                confidence=0.98,
                label="verified_success",
                view_set=["full", "evidence"],
            )

        # 3. User explicit intent (L3)
        if atom.authority == AuthorityLevel.L3:
            atom.verified_by = "human"
            return VerifierSignal(
                reward=0.95,
                confidence=0.90,
                label="verified_success",
                view_set=["full"],
            )

        # 4. Mined transcript hypotheses (source: transcript_miner) enter as candidate L2
        if atom.source == "transcript_miner":
            atom.authority = AuthorityLevel.L2
            atom.verified_by = "transcript_miner"

            # Check for ambiguous multi-file causal attribution (Gate 2 attribution guard)
            # If multiple files were modified between failure and pass, attribution is ambiguous
            has_multi_file = (
                len([ref for ref in atom.evidence_refs if "/" in ref or "." in ref]) > 1
                or (atom.conflict_note and "multi-file" in atom.conflict_note.lower())
            )
            if has_multi_file:
                atom.state = LifecycleState.PENDING_ADJUDICATION
                return VerifierSignal(
                    reward=0.50,
                    confidence=0.50,
                    label="ambiguous_causal_attribution",
                    view_set=["risk"],
                )

            atom.state = LifecycleState.CANDIDATE
            return VerifierSignal(
                reward=0.65,
                confidence=0.60,
                label="candidate_hypothesis",
                view_set=["full"],
            )

        # 5. Agent operational observation (L2)
        if not atom.verified_by or atom.verified_by == "compiler":
            atom.verified_by = atom.agent_id or "host_agent:claude_code"

        has_resolution = bool(atom.resolution and len(atom.resolution.strip()) > 5)
        has_trigger = bool(atom.trigger_pattern and len(atom.trigger_pattern.strip()) > 3)

        # Check 5a: Trigger verbosity threshold -> Gate 4 deferred adjudication
        if atom.trigger_pattern and len(atom.trigger_pattern.strip()) > 120:
            atom.state = LifecycleState.PENDING_ADJUDICATION
            return VerifierSignal(
                reward=0.55,
                confidence=0.50,
                label="trigger_too_verbose_pending_adjudication",
                view_set=["risk"],
            )

        # Check 5b: Trigger Substring Grounding in Failure Signature (if present)
        if atom.failure_signature and atom.trigger_pattern:
            sig_norm = atom.failure_signature.strip().lower()
            trig_norm = atom.trigger_pattern.strip().lower()
            trigger_grounded = (trig_norm in sig_norm) or any(
                token in sig_norm
                for token in re.findall(r'[a-zA-Z0-9_]{4,}', trig_norm)
            )
            if not trigger_grounded:
                return VerifierSignal(
                    reward=0.45,
                    confidence=0.40,
                    label="trigger_not_found_in_error",
                    view_set=["risk"],
                )

        # Check 5c: Structural Code Identifier Requirement in Resolution
        has_code_identifier = bool(self.CODE_IDENTIFIER_PATTERN.search(atom.resolution)) if atom.resolution else False
        if not has_code_identifier:
            return VerifierSignal(
                reward=0.40,
                confidence=0.35,
                label="vague_resolution_lacks_identifier",
                view_set=["risk"],
            )

        if has_resolution and has_trigger:
            return VerifierSignal(
                reward=0.85,
                confidence=0.80,
                label="verified_success",
                view_set=["full"],
            )
        else:
            return VerifierSignal(
                reward=0.5,
                confidence=0.45,
                label="uncertain",
                view_set=["risk"],
            )

    def detect_contradiction(self, new_atom: MemoryAtom, existing_atom: MemoryAtom) -> ContradictionKind | None:
        """Stage 1: Explicit contradiction detection based on Subject-Predicate-Object and negation."""
        # Check structured Subject-Predicate-Object if populated
        if new_atom.subject and existing_atom.subject and new_atom.subject == existing_atom.subject:
            if new_atom.predicate and existing_atom.predicate and new_atom.predicate == existing_atom.predicate:
                if new_atom.object_value and existing_atom.object_value and new_atom.object_value != existing_atom.object_value:
                    return ContradictionKind.DIRECT_VALUE_CONFLICT

        # Check semantic contradiction on resolution text
        res_a = new_atom.resolution.lower()
        res_b = existing_atom.resolution.lower()
        if res_a != res_b and self._is_contradictory_text(res_a, res_b):
            return ContradictionKind.DIRECT_VALUE_CONFLICT

        return None

    def adjudicate_write(self, candidate: MemoryAtom) -> tuple[MemoryAtom, list[MemoryAtom], list[MemoryEdge]]:
        """
        Runs write-side adjudication before candidate enters active store.
        Returns (persisted_candidate, affected_old_atoms, new_edges).
        """
        # Step 1: Run verifier
        verifier = self.verify_candidate(candidate)
        candidate.reward = verifier.reward
        candidate.confidence = verifier.confidence
        candidate.label = verifier.label
        candidate.view_set = verifier.view_set

        if candidate.authority == AuthorityLevel.L4:
            candidate.state = LifecycleState.QUARANTINED
            self.db.save_atom(candidate)
            return candidate, [], []

        # Save candidate first so its ID is in memory_atoms for foreign key constraints
        self.db.save_atom(candidate)

        affected: list[MemoryAtom] = []
        new_edges: list[MemoryEdge] = []
        now = datetime.now(timezone.utc)

        # Step 1.5: Double-Verification Pattern for Mined Hypotheses
        if candidate.source == "transcript_miner":
            all_existing = self.db.fetch_atoms(project=candidate.project, file_path=candidate.file_path, active_only=False)
            relevant_old = [
                a for a in all_existing
                if a.id != candidate.id and a.state in (LifecycleState.ACTIVE, LifecycleState.CANDIDATE, LifecycleState.STALE)
                and (a.trigger_pattern.strip() == candidate.trigger_pattern.strip() or self._patterns_overlap(a, candidate))
            ]
            if relevant_old:
                matched_old = relevant_old[0]
                same_fix = matched_old.resolution.strip().lower() == candidate.resolution.strip().lower()
                diff_session = bool(matched_old.session_id and candidate.session_id and matched_old.session_id != candidate.session_id)

                if same_fix:
                    if diff_session:
                        # Double-Verification Promotion: Proven across independent sessions!
                        matched_old.state = LifecycleState.ACTIVE
                        matched_old.confidence = 0.95
                        matched_old.occurrence_count += 1
                        matched_old.hit_count += 1
                        matched_old.conflict_note = "✓ Double-verified across independent sessions."
                        matched_old.updated_at = now
                        self.db.save_atom(matched_old)

                        evidence_edge = MemoryEdge(
                            from_atom_id=candidate.id,
                            to_atom_id=matched_old.id,
                            edge_type=EdgeType.EVIDENCE_FOR,
                            valid_from=now,
                        )
                        self.db.save_edge(evidence_edge)
                        new_edges.append(evidence_edge)
                        affected.append(matched_old)

                        candidate.state = LifecycleState.SUPERSEDED
                        candidate.invalidated_by = matched_old.id
                        self.db.save_atom(candidate)
                        return candidate, affected, new_edges
                    else:
                        matched_old.occurrence_count += 1
                        matched_old.updated_at = now
                        self.db.save_atom(matched_old)
                        candidate.state = LifecycleState.SUPERSEDED
                        candidate.invalidated_by = matched_old.id
                        self.db.save_atom(candidate)
                        return candidate, affected, new_edges
                else:
                    # Recurrence with a different fix: previous hypothesis was flawed or incomplete!
                    matched_old.valid_until = now
                    matched_old.invalidated_by = candidate.id
                    matched_old.state = LifecycleState.SUPERSEDED
                    matched_old.updated_at = now
                    self.db.save_atom(matched_old)
                    affected.append(matched_old)

                    contra_edge = MemoryEdge(
                        from_atom_id=candidate.id,
                        to_atom_id=matched_old.id,
                        edge_type=EdgeType.CONTRADICTS,
                        valid_from=now,
                    )
                    self.db.save_edge(contra_edge)
                    new_edges.append(contra_edge)

                    candidate.state = LifecycleState.CANDIDATE
                    candidate.confidence = 0.60
                    self.db.save_atom(candidate)
                    return candidate, affected, new_edges

        # Step 2: CUPMem Slot Conflict Search (same file or same subject)
        existing_atoms = self.db.fetch_atoms(
            project=candidate.project,
            file_path=candidate.file_path,
            active_only=True,
        )

        for old in existing_atoms:
            if old.id == candidate.id:
                continue

            # Check slot overlap: same file and matching symbol or trigger overlap
            same_symbol = bool(old.symbol and candidate.symbol and old.symbol == candidate.symbol)
            same_subject = bool(old.subject and candidate.subject and old.subject == candidate.subject)
            shares_slot = same_symbol or same_subject or self._patterns_overlap(old, candidate)

            if not shares_slot:
                continue

            # Detect explicit contradiction
            contra_kind = self.detect_contradiction(candidate, old)
            decision = self._decide_conflict(candidate, old, contradiction=contra_kind)

            if decision == AdjudicationDecision.REPLACE:
                # Invalidate old memory atom
                old.valid_until = now
                old.invalidated_by = candidate.id
                old.state = LifecycleState.SUPERSEDED
                old.updated_at = now
                self.db.save_atom(old)
                affected.append(old)

                # Explicit SUPERSEDES edge
                edge = MemoryEdge(
                    from_atom_id=candidate.id,
                    to_atom_id=old.id,
                    edge_type=EdgeType.SUPERSEDES,
                    valid_from=now,
                )
                self.db.save_edge(edge)
                new_edges.append(edge)

            elif decision == AdjudicationDecision.STALE:
                old.valid_until = now
                old.state = LifecycleState.STALE
                old.updated_at = now
                self.db.save_atom(old)
                affected.append(old)

            elif decision == AdjudicationDecision.UNKNOWN:
                # Both kept, but flagged as CONFLICTED with dual-claim note
                old.state = LifecycleState.CONFLICTED
                candidate.state = LifecycleState.CONFLICTED

                source_a = f"Session {old.session_id or 'previous'} ({old.authority.value}, {old.label}): {old.resolution}"
                source_b = f"Session {candidate.session_id or 'current'} ({candidate.authority.value}, {candidate.label}): {candidate.resolution}"
                note = f"• {source_a}\n  • {source_b}"

                old.conflict_note = note
                candidate.conflict_note = note
                old.updated_at = now
                candidate.updated_at = now

                self.db.save_atom(old)
                self.db.save_atom(candidate)
                affected.append(old)

                edge = MemoryEdge(
                    from_atom_id=candidate.id,
                    to_atom_id=old.id,
                    edge_type=EdgeType.CONTRADICTS,
                    valid_from=now,
                )
                self.db.save_edge(edge)
                new_edges.append(edge)

        return candidate, affected, new_edges

    def _decide_conflict(
        self,
        new_atom: MemoryAtom,
        old_atom: MemoryAtom,
        contradiction: ContradictionKind | None = None,
    ) -> AdjudicationDecision:
        """CUPMem Authority Hierarchy Resolution."""
        # 1. Higher authority always supersedes lower authority
        # e.g., L1 (compiler) supersedes L2 (agent observation)
        if new_atom.authority.trust_score > old_atom.authority.trust_score:
            return AdjudicationDecision.REPLACE

        # 2. Lower authority cannot silently override higher authority
        if new_atom.authority.trust_score < old_atom.authority.trust_score:
            # If user intent (L3) conflicts with compiler (L1), preserve both with warning
            if new_atom.authority == AuthorityLevel.L3 and old_atom.authority == AuthorityLevel.L1:
                return AdjudicationDecision.UNKNOWN
            return AdjudicationDecision.KEEP

        # 3. Equal authority:
        # If contradiction detected between equal-authority agents, mark UNKNOWN (CONFLICTED)
        if contradiction is not None:
            return AdjudicationDecision.UNKNOWN

        if new_atom.confidence >= old_atom.confidence:
            return AdjudicationDecision.REPLACE
        return AdjudicationDecision.KEEP

    def _patterns_overlap(self, a: MemoryAtom, b: MemoryAtom) -> bool:
        words_a = set(re.findall(r"\w+", a.trigger_pattern.lower()))
        words_b = set(re.findall(r"\w+", b.trigger_pattern.lower()))
        if not words_a or not words_b:
            return False
        jaccard = len(words_a & words_b) / len(words_a | words_b)
        return jaccard >= 0.35

    def _is_contradictory_text(self, res_a: str, res_b: str) -> bool:
        negations = ["not", "never", "instead of", "don't", "avoid", "deprecated", "removed"]
        return any(neg in res_a or neg in res_b for neg in negations)

    def adjudicate_host_agent(
        self,
        candidate_id: str,
        host_agent: str,
        decision: str,
        reason: str = "",
        target_file: str | None = None,
    ) -> dict[str, Any]:
        """
        Gate 4: Deferred AI Adjudication via Host Agent MCP.
        Strictly bounded to 3 questions:
        1. Multi-file causal attribution ("attribute"): which edit caused the pass?
        2. Content-dependency re-verification ("valid" | "stale"): does D still hold given C'?
        3. UNKNOWN conflict adjudication ("resolve_conflict" | "distinct_scope"): contradictory vs different scope?

        Decisions outside this scope are retained in pending_adjudication for human review.
        """
        atom = self.db.get_atom(candidate_id)
        if not atom:
            return {"error": f"Atom not found: {candidate_id}"}

        dec = decision.lower().strip()
        now = datetime.now(timezone.utc)
        provenance = f"host_agent:{host_agent}"

        if dec in ("attribute", "attributed"):
            # Question 1: Given multi-file diff, which edit caused the pass?
            if target_file:
                atom.file_path = target_file
            atom.state = LifecycleState.ACTIVE
            atom.verified_by = provenance
            atom.confidence = max(atom.confidence, 0.85)
            atom.conflict_note = f"✓ Causally attributed by {provenance}: {reason}".strip()
            atom.updated_at = now
            self.db.save_atom(atom)
            return {
                "status": "ADJUDICATED",
                "atom_id": atom.id,
                "state": atom.state.value,
                "verified_by": atom.verified_by,
                "confidence": atom.confidence,
                "note": atom.conflict_note,
            }

        elif dec in ("valid", "verified"):
            # Question 2: Content-dependency re-verification (D still holds given C')
            atom.state = LifecycleState.ACTIVE
            atom.verified_by = provenance
            atom.confidence = max(atom.confidence, 0.85)
            atom.conflict_note = f"✓ Content dependency re-verified by {provenance}: {reason}".strip()
            atom.updated_at = now
            self.db.save_atom(atom)
            return {
                "status": "ADJUDICATED",
                "atom_id": atom.id,
                "state": atom.state.value,
                "verified_by": atom.verified_by,
                "note": atom.conflict_note,
            }

        elif dec in ("invalid", "stale", "refuted"):
            # Question 2 (refuted): Content dependency broken by C'
            atom.state = LifecycleState.STALE
            atom.valid_until = now
            atom.conflict_note = f"Refuted by {provenance}: {reason}".strip()
            atom.updated_at = now
            self.db.save_atom(atom)
            return {
                "status": "ADJUDICATED",
                "atom_id": atom.id,
                "state": atom.state.value,
                "note": atom.conflict_note,
            }

        elif dec in ("distinct_scope", "scope_disambiguated"):
            # Question 3: Not contradictory, just different in scope
            atom.state = LifecycleState.ACTIVE
            atom.verified_by = provenance
            atom.conflict_note = f"✓ Distinct scope confirmed by {provenance}: {reason}".strip()
            atom.updated_at = now
            self.db.save_atom(atom)
            return {
                "status": "ADJUDICATED",
                "atom_id": atom.id,
                "state": atom.state.value,
                "verified_by": atom.verified_by,
                "note": atom.conflict_note,
            }

        elif dec in ("resolve_conflict", "supersede"):
            # Question 3: Semantically contradictory, candidate chosen as winner
            atom.state = LifecycleState.ACTIVE
            atom.verified_by = provenance
            atom.confidence = max(atom.confidence, 0.85)
            atom.conflict_note = f"✓ Conflict resolved in favor of {atom.id} by {provenance}: {reason}".strip()
            atom.updated_at = now
            self.db.save_atom(atom)
            return {
                "status": "ADJUDICATED",
                "atom_id": atom.id,
                "state": atom.state.value,
                "verified_by": atom.verified_by,
                "note": atom.conflict_note,
            }

        else:
            # Outside the 3 bounded questions: hold in pending_adjudication for human review
            atom.state = LifecycleState.PENDING_ADJUDICATION
            atom.conflict_note = f"Pending human review (unsupported decision '{decision}'): {reason}".strip()
            atom.updated_at = now
            self.db.save_atom(atom)
            return {
                "status": "PENDING_HUMAN_REVIEW",
                "atom_id": atom.id,
                "state": atom.state.value,
                "message": "Question outside bounded Gate 4 scope. Deferred to pending_adjudication for human review.",
            }

