"""Data models for Flightdeck Epistemic Causal Substrate (ECS)."""

from __future__ import annotations
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
import uuid
from typing import Any


class AuthorityLevel(str, Enum):
    """Authority level governing write-side trust."""
    L0 = "L0"    # File system state, git commit (Ground truth, read-only)
    L1 = "L1"    # Direct machine ground truth: AST symbols, compiler exit code, test pass (High, read-only)
    L2 = "L2"    # Legacy / generic agent observation
    L2a = "L2a"  # Host agent LLM judgment (Contextual, high-reasoning, non-deterministic)
    L2b = "L2b"  # Transcript miner sequential inference (Deterministic pattern match, reproducible)
    L3 = "L3"    # User explicit directive (High user intent, writable)
    L4 = "L4"    # External document / web page (Low, writable, quarantined)

    @classmethod
    def from_str(cls, val: str) -> "AuthorityLevel":
        normalized = val.strip().lower()
        mapping = {
            "l0": cls.L0,
            "l1": cls.L1,
            "l2": cls.L2,
            "l2a": cls.L2a,
            "l2b": cls.L2b,
            "l3": cls.L3,
            "l4": cls.L4,
        }
        if normalized in mapping:
            return mapping[normalized]
        raise ValueError(f"Unknown authority level: {val}")

    @property
    def is_quarantined(self) -> bool:
        return self == AuthorityLevel.L4

    @property
    def trust_score(self) -> float:
        return {
            AuthorityLevel.L0: 1.0,
            AuthorityLevel.L1: 0.95,
            AuthorityLevel.L3: 0.85,
            AuthorityLevel.L2a: 0.75,
            AuthorityLevel.L2b: 0.70,
            AuthorityLevel.L2: 0.70,
            AuthorityLevel.L4: 0.30,
        }[self]


class MemoryKind(str, Enum):
    """Epistemic category of a causal memory atom."""
    TRAP = "trap"          # Hazard/compiler error to avoid
    RULE = "rule"          # Verified working pattern/flag
    INVARIANT = "invariant"# System constraint/dependency
    LESSON = "lesson"      # Dual-memory failure lesson
    DEAD_END = "dead_end"  # Falsified hypothesis
    RECIPE = "recipe"      # Procedural multi-step blueprint / scaffolding recipe

    @property
    def badge(self) -> str:
        badges = {
            MemoryKind.TRAP: "⚠️ TRAP",
            MemoryKind.RULE: "✓ RULE",
            MemoryKind.INVARIANT: "⚓︎ INVARIANT",
            MemoryKind.LESSON: "🛑 LESSON",
            MemoryKind.DEAD_END: "✕ DEAD END",
            MemoryKind.RECIPE: "📋 RECIPE",
        }
        return badges[self]


class LifecycleState(str, Enum):
    """Lifecycle state of an atom in the bitemporal causal graph."""
    CANDIDATE = "candidate"
    ACTIVE = "active"
    PENDING_ADJUDICATION = "pending_adjudication"  # Queued for Gate 4 host-agent adjudication
    STALE = "stale"
    SUPERSEDED = "superseded"
    QUARANTINED = "quarantined"
    CONFLICTED = "conflicted"
    OBSOLETE = "obsolete"


class EdgeType(str, Enum):
    """Typed causal edges."""
    CAUSES = "CAUSES"              # A caused B
    SOLVES = "SOLVES"              # Fix solves problem
    DEPENDS_ON = "DEPENDS_ON"      # Component depends on dependency
    CONTRADICTS = "CONTRADICTS"    # Mutually exclusive claims
    SUPERSEDES = "SUPERSEDES"      # New atom supersedes old
    EVIDENCE_FOR = "EVIDENCE_FOR"  # Provenance link
    LEADS_TO_DEAD_END = "LEADS_TO_DEAD_END"  # Attempted resolution hypothesis led to failure


class AdjudicationDecision(str, Enum):
    """CUPMem write-side adjudication decision."""
    KEEP = "KEEP"        # Both valid (orthogonal/different scopes)
    STALE = "STALE"      # Old memory is outdated but was true (close valid_until)
    REPLACE = "REPLACE"  # New memory supersedes old (explicitly chain invalidated_by)
    UNKNOWN = "UNKNOWN"  # Cannot determine; flag as conflicted


class AnchorStatus(str, Enum):
    """Hash-anchored verification status relative to git committed blobs."""
    VERIFIED = "verified"             # Content hash matches committed blob exactly
    STALE = "stale"                   # Content hash changed, but referenced symbol persists
    CONTRADICTED = "contradicted"     # Code changed and referenced symbol is completely gone
    MISSING_SOURCE = "missing_source" # File deleted from repository
    UNVERIFIED = "unverified"         # Not yet verified against git repository


class ContradictionKind(str, Enum):
    """Type of contradiction between memory claims."""
    DIRECT_VALUE_CONFLICT = "direct_value_conflict"  # Same subject + predicate, conflicting object value
    PREDICATE_CONFLICT = "predicate_conflict"        # Mutually exclusive predicates on same subject


@dataclass
class MemoryAnchor:
    """Git-anchored code verification contract (Context Fabric & Legendary-MCP pattern)."""
    file_path: str
    symbol_name: str | None = None
    content_hash: str = ""       # SHA256 of committed blob or code region
    commit_sha: str = "HEAD"     # Commit at write time
    line_start: int | None = None
    line_end: int | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "file_path": self.file_path,
            "symbol_name": self.symbol_name,
            "content_hash": self.content_hash,
            "commit_sha": self.commit_sha,
            "line_start": self.line_start,
            "line_end": self.line_end,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any] | None) -> MemoryAnchor | None:
        if not data:
            return None
        return cls(
            file_path=data.get("file_path", ""),
            symbol_name=data.get("symbol_name"),
            content_hash=data.get("content_hash", ""),
            commit_sha=data.get("commit_sha", "HEAD"),
            line_start=data.get("line_start"),
            line_end=data.get("line_end"),
        )


@dataclass
class VerifierSignal:
    """MemGuard-style verifier signals."""
    reward: float = 1.0         # R_m: trajectory reward [0, 1]
    confidence: float = 1.0     # c_m: confidence [0, 1]
    label: str = "verified_success"  # l_m: verified_success, verified_fail, uncertain
    view_set: list[str] = field(default_factory=lambda: ["full"])  # nu_m: full, evidence, risk


@dataclass
class MemoryAtom:
    """Bitemporal Causal Memory Atom with Hash-Anchored Provenance."""
    project: str
    file_path: str
    kind: MemoryKind
    trigger_pattern: str
    resolution: str
    authority: AuthorityLevel = AuthorityLevel.L2
    symbol: str | None = None
    failure_signature: str | None = None
    state: LifecycleState = LifecycleState.ACTIVE

    # Structured Subject-Predicate-Object for exact contradiction detection
    subject: str | None = None
    predicate: str | None = None
    object_value: str | None = None

    # Hash-anchored symbol verification
    anchor: MemoryAnchor | None = None
    anchor_status: AnchorStatus = AnchorStatus.UNVERIFIED

    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    git_sha: str = "HEAD"
    file_hash: str | None = None
    agent_id: str | None = None
    session_id: str | None = None
    source: str = "agent"  # "agent", "transcript_miner", "user_directive", "git_probe"
    verified_by: str = "compiler"  # "compiler" (L1), "filesystem" (L1), "host_agent:<name>" (L2), "transcript_miner" (L2), "human" (L3)
    occurrence_count: int = 1
    evidence_refs: list[str] = field(default_factory=list)
    conflict_note: str | None = None

    # Bitemporal axes
    valid_from: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    valid_until: datetime | None = None
    trial_until: datetime | None = None  # Provisional trial expiration for host-agent adjudications
    recorded_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    invalidated_by: str | None = None

    # Persistent verifier signals
    reward: float = 1.0
    confidence: float = 1.0
    label: str = "verified_success"
    view_set: list[str] = field(default_factory=lambda: ["full"])

    hit_count: int = 0
    success_count: int = 0
    failure_count: int = 0
    last_feedback_at: datetime | None = None
    verification_cmd: str | None = None
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))

    @property
    def efficacy_score(self) -> float:
        """Bayesian Laplace-smoothed efficacy rate in [0.0, 1.0]."""
        return (self.success_count + 1.0) / (self.success_count + self.failure_count + 2.0)

    @property
    def is_provisional(self) -> bool:
        """Indicates whether this atom is under a provisional trial period."""
        if not self.trial_until:
            return False
        return self.trial_until > datetime.now(timezone.utc)

    @property
    def micro_directive(self) -> str:
        """
        Dense micro-directive format (<60 tokens) with imperative staleness
        and conflict warnings (Legendary-MCP / Context Fabric pattern).
        """
        # 1. Conflicted State — Present both claims explicitly so the agent doesn't silently pick wrong
        if self.state == LifecycleState.CONFLICTED:
            header = f"[CONFLICT: {self.subject or self.symbol or self.file_path}]"
            lines = [header, "⚠️ Two sources disagree on this code region:"]
            if self.conflict_note:
                lines.append(f"  {self.conflict_note}")
            else:
                lines.append(f"  • Claim: {self.resolution}")
            lines.append("  Review code before proceeding.")
            return "\n".join(lines)

        # 2. Dead End State — Falsified hypothesis that failed (Pruning directive)
        if self.kind == MemoryKind.DEAD_END:
            header = f"[✕ DEAD END: {self.symbol or self.file_path}] (Falsified Hypothesis - Do NOT attempt)"
            lines = [header]
            if self.trigger_pattern:
                lines.append(f"  Context: {self.trigger_pattern}")
            lines.append(f"  Attempted Fix: {self.resolution}")
            if self.failure_signature:
                lines.append(f"  Failure Result: {self.failure_signature}")
            return "\n".join(lines)

        # 3. Procedural Golden Recipe Blueprint
        if self.kind == MemoryKind.RECIPE:
            header = f"[📋 RECIPE: {self.symbol or self.file_path}] (Golden Blueprint)"
            lines = [header]
            if self.trigger_pattern:
                lines.append(f"  Intent: {self.trigger_pattern}")
            lines.append("  Procedure:")
            for line in self.resolution.strip().splitlines():
                clean_l = line.strip()
                if clean_l:
                    lines.append(f"    {clean_l}")
            return "\n".join(lines)

        # 4. Stale State — Code changed, but symbol persists
        if self.anchor_status == AnchorStatus.STALE or self.state == LifecycleState.STALE:
            header = f"[STALE: {self.symbol or self.file_path}]"
            lines = [
                header,
                "  ⚠️ Code changed since this was written; verify before trusting.",
                f"  Trigger: {self.trigger_pattern}",
                f"  Prior Fix: {self.resolution}",
            ]
            return "\n".join(lines)

        # 3. Verified Active State (with provisional trial tag if applicable)
        status_tag = ""
        if self.anchor_status == AnchorStatus.VERIFIED:
            status_tag = " (verified against committed code)"

        header = f"[{self.kind.badge}: {self.symbol or self.file_path}]{status_tag}"
        lines = [header]
        if self.trigger_pattern:
            lines.append(f"  Trigger: {self.trigger_pattern}")
        if self.failure_signature:
            lines.append(f"  Failure: {self.failure_signature}")
        lines.append(f"  Fix: {self.resolution}")
        if self.failure_count > 0:
            lines.append(f"  ⚠️ Efficacy Warning: {self.failure_count} reported failure(s) ({int(self.efficacy_score * 100)}% pass rate)")
        if self.is_provisional and self.trial_until:
            lines.append(f"  ⚠️ [PROVISIONAL TRIAL]: Adjudicated by host agent until {self.trial_until.strftime('%Y-%m-%d')}; subject to demotion if contradiction occurs.")
        return "\n".join(lines)

    @property
    def token_estimate(self) -> int:
        """Rough token estimate (~4 chars per token)."""
        return len(self.micro_directive) // 4

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "project": self.project,
            "file_path": self.file_path,
            "symbol": self.symbol,
            "subject": self.subject,
            "predicate": self.predicate,
            "object_value": self.object_value,
            "kind": self.kind.value,
            "authority": self.authority.value,
            "verified_by": self.verified_by,
            "occurrence_count": self.occurrence_count,
            "trigger_pattern": self.trigger_pattern,
            "failure_signature": self.failure_signature,
            "resolution": self.resolution,
            "state": self.state.value,
            "anchor_status": self.anchor_status.value,
            "anchor": self.anchor.to_dict() if self.anchor else None,
            "conflict_note": self.conflict_note,
            "git_sha": self.git_sha,
            "file_hash": self.file_hash,
            "agent_id": self.agent_id,
            "session_id": self.session_id,
            "evidence_refs": self.evidence_refs,
            "valid_from": self.valid_from.isoformat(),
            "valid_until": self.valid_until.isoformat() if self.valid_until else None,
            "trial_until": self.trial_until.isoformat() if self.trial_until else None,
            "is_provisional": self.is_provisional,
            "recorded_at": self.recorded_at.isoformat(),
            "invalidated_by": self.invalidated_by,
            "reward": self.reward,
            "confidence": self.confidence,
            "label": self.label,
            "view_set": self.view_set,
            "hit_count": self.hit_count,
            "success_count": self.success_count,
            "failure_count": self.failure_count,
            "efficacy_score": self.efficacy_score,
            "last_feedback_at": self.last_feedback_at.isoformat() if self.last_feedback_at else None,
            "verification_cmd": self.verification_cmd,
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat(),
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "MemoryAtom":
        def _parse_dt(val: Any) -> datetime | None:
            if not val:
                return None
            if isinstance(val, datetime):
                return val
            return datetime.fromisoformat(val)

        anchor_obj = MemoryAnchor.from_dict(data.get("anchor"))

        return cls(
            id=data.get("id") or str(uuid.uuid4()),
            project=data.get("project", "default"),
            file_path=data.get("file_path") or data.get("filePath", ""),
            symbol=data.get("symbol"),
            subject=data.get("subject"),
            predicate=data.get("predicate"),
            object_value=data.get("object_value") or data.get("objectValue"),
            kind=MemoryKind(data.get("kind", "rule")),
            authority=AuthorityLevel.from_str(data.get("authority", "L2")),
            verified_by=data.get("verified_by") or data.get("verifiedBy", "compiler"),
            occurrence_count=int(data.get("occurrence_count") or data.get("occurrenceCount", 1)),
            trigger_pattern=data.get("trigger_pattern") or data.get("triggerPattern", ""),
            failure_signature=data.get("failure_signature") or data.get("failureSignature"),
            resolution=data.get("resolution", ""),
            state=LifecycleState(data.get("state") or data.get("status", "active")),
            anchor_status=AnchorStatus(data.get("anchor_status") or data.get("anchorStatus", "unverified")),
            anchor=anchor_obj,
            conflict_note=data.get("conflict_note") or data.get("conflictNote"),
            git_sha=data.get("git_sha") or data.get("gitSha", "HEAD"),
            file_hash=data.get("file_hash") or data.get("fileHash"),
            agent_id=data.get("agent_id") or data.get("agentId"),
            session_id=data.get("session_id") or data.get("sessionId") or data.get("originSessionId"),
            evidence_refs=data.get("evidence_refs") or data.get("evidenceRefs") or [],
            valid_from=_parse_dt(data.get("valid_from") or data.get("validFrom")) or datetime.now(timezone.utc),
            valid_until=_parse_dt(data.get("valid_until") or data.get("validUntil")),
            trial_until=_parse_dt(data.get("trial_until") or data.get("trialUntil")),
            recorded_at=_parse_dt(data.get("recorded_at") or data.get("recordedAt")) or datetime.now(timezone.utc),
            invalidated_by=data.get("invalidated_by") or data.get("invalidatedBy"),
            reward=float(data.get("reward", 1.0)),
            confidence=float(data.get("confidence", 1.0)),
            label=data.get("label", "verified_success"),
            view_set=data.get("view_set") or ["full"],
            hit_count=int(data.get("hit_count") or data.get("hitCount", 0)),
            success_count=int(data.get("success_count") or data.get("successCount", 0)),
            failure_count=int(data.get("failure_count") or data.get("failureCount", 0)),
            last_feedback_at=_parse_dt(data.get("last_feedback_at") or data.get("lastFeedbackAt")),
            verification_cmd=data.get("verification_cmd") or data.get("verificationCmd"),
            created_at=_parse_dt(data.get("created_at") or data.get("createdAt")) or datetime.now(timezone.utc),
            updated_at=_parse_dt(data.get("updated_at") or data.get("updatedAt")) or datetime.now(timezone.utc),
        )


@dataclass
class MemoryEdge:
    """Bitemporal Causal Edge connecting Memory Atoms."""
    from_atom_id: str
    to_atom_id: str
    edge_type: EdgeType
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    valid_from: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    valid_until: datetime | None = None
    recorded_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    invalidated_by: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "from_atom_id": self.from_atom_id,
            "to_atom_id": self.to_atom_id,
            "edge_type": self.edge_type.value,
            "valid_from": self.valid_from.isoformat(),
            "valid_until": self.valid_until.isoformat() if self.valid_until else None,
            "recorded_at": self.recorded_at.isoformat(),
            "invalidated_by": self.invalidated_by,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "MemoryEdge":
        def _parse_dt(val: Any) -> datetime | None:
            if not val:
                return None
            if isinstance(val, datetime):
                return val
            return datetime.fromisoformat(val)

        return cls(
            id=data.get("id") or str(uuid.uuid4()),
            from_atom_id=data.get("from_atom_id") or data.get("fromCapsuleId", ""),
            to_atom_id=data.get("to_atom_id") or data.get("toCapsuleId", ""),
            edge_type=EdgeType(data.get("edge_type") or data.get("edgeType")),
            valid_from=_parse_dt(data.get("valid_from") or data.get("validFrom")) or datetime.now(timezone.utc),
            valid_until=_parse_dt(data.get("valid_until") or data.get("validUntil")),
            recorded_at=_parse_dt(data.get("recorded_at") or data.get("recordedAt")) or datetime.now(timezone.utc),
            invalidated_by=data.get("invalidated_by") or data.get("invalidatedBy"),
        )


@dataclass
class BlastRadiusResult:
    """Result of recursive CTE causal blast radius traversal with truncation metadata."""
    nodes: list[str]
    truncated: bool = False
    total_estimate: int = 0

    def __iter__(self):
        return iter(self.nodes)

    def __len__(self):
        return len(self.nodes)

    def __getitem__(self, idx):
        return self.nodes[idx]

    def __contains__(self, item):
        return item in self.nodes

    def __eq__(self, other):
        if isinstance(other, list):
            return self.nodes == other
        if isinstance(other, BlastRadiusResult):
            return (self.nodes, self.truncated, self.total_estimate) == (other.nodes, other.truncated, other.total_estimate)
        return False
