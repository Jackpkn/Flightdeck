Flightdeck: Local Causal Memory Layer for Coding Agents
Flightdeck is a local-first, deterministic, zero-cloud causal memory substrate designed to permanently break the "Groundhog Day" loop in AI coding agents (Claude Code, Cursor, Codex, Antigravity, etc.).

Instead of forcing coding agents to repeatedly hit and debug the exact same compiler errors, build-flag quirks, or architectural footguns across independent sessions, Flightdeck acts as an external hippocampus that records, grounds, and injects actionable micro-directives before mistakes occur.

1. The Core Problem: The Agent Amnesia Trap
Modern AI coding agents have a structural blind spot:

Session Amnesia: An agent in Session 1 spends 8 turns and 40k tokens diagnosing a subtle Swift/Rust compiler error (e.g., ContextWindowSource has no member .measured, use .inferred instead). Once the session ends, that knowledge vanishes. Session 2 makes the exact same mistake 10 minutes later.
The Failure of Traditional "Vector Memory":
High Latency: Cloud vector databases and remote embedding APIs inject 300ms–800ms roundtrips into every agent prompt turn.
Conversational Pollution: Naive RAG dumps conversational chatter, user greetings, and obsolete scratchpad thoughts into prompt contexts.
No Causal Grounding: Vector similarity cannot distinguish between a fix that actually made the compiler exit 0 and a hallucinated suggestion that broke the build.
Git Drift Blindness: If code refactoring deletes or renames a symbol, traditional memory stores continue injecting obsolete rules indefinitely.
Flightdeck replaces vague vector similarity with a deterministic, Git-anchored, bitemporal causal graph.

2. Core Architectural Pillars
                     ┌─────────────────────────────────────────────────────────┐
                     │          FLIGHTDECK CAUSAL MEMORY ARCHITECTURE          │
                     └─────────────────────────────────────────────────────────┘
   Developer / Agent Session                                         Background / Offline
 ─────────────────────────────                                     ─────────────────────────
  [ Compiler Error Occurs ]
             │
             ▼
   Gate 1: Exit Code Check ──── (Exit != 0 -> Edit -> Exit == 0)
             │
             ▼
   Gate 2: Structural Verifier ─── (Code identifiers, substring grounding, multi-file guard)
             │
             ├────────────────────────────────────────┐
             ▼ (Structured Code Identifier)           ▼ (Unpatterned Substantive Advice)
   Gate 3: CUPMem Adjudication               [ Pending Adjudication ]
      (L1 > L2a / L2b > L4)                           │
             │                                        │ (SessionStart Hook Alert)
             ▼                                        ▼
    [ Active Memory Graph ] ◄─────────────── Gate 4: Host Agent via MCP
    (SQLite WAL + FTS5 Index)                 - Multi-file Attribution
             │                                - Content Re-verification
             ▼                                - UNKNOWN Conflict Resolution
  Budget-Aware Retrieval                      - Advice Validation (7-Day Trial)
   (Sub-10ms Local Fast-Path)                         │
             │                                        ▼
             ▼                              Offline "Dream Phase"
   [ Micro-Directives Injected ]              - Tombstone Compaction (7-day floor)
   Before Agent Edits Code                   - 90-Day Conflict Aging
                                             - Trial Solidification
A. The 4-Gate Ingestion Pipeline
Flightdeck uses a deterministic 4-stage pipeline that strictly dictates what can enter the memory graph:

Gate	Verification Mechanism	Authority Level	Role
Gate 1: Exit Codes	Compiler / Test Runner Exit Code (0 vs != 0)	L1 (Physical Ground Truth)	Guarantees that only fixes that physically turned a failing build into a passing build are considered. Zero LLMs here to prevent hallucinated fixes.
Gate 2: Structural Verifier	Structural Code Identifiers & Error Grounding	Structural Machine Check	Rejects pure platitudes ("try again"). Requires file paths, function calls, enum cases (.case), CLI flags (--flag), or PascalCase symbols. Actionable unpatterned advice routes to pending adjudication rather than being discarded.
Gate 3: CUPMem Adjudication	Slot Conflict & Authority Hierarchy Resolution	Graph Consistency Tier	Resolves slot collisions (same file + symbol/trigger). $L1$ compiler ground truth supersedes $L2$. Equal-tier conflicts yield CONFLICTED status with dual-claim warnings. Executes cross-session double-verification.
Gate 4: Host Agent via MCP	Deferred AI Adjudication via Active Agent	L2a (LLM Contextual Judgment)	Invokes the developer's already-active coding agent via MCP to resolve 4 bounded questions: multi-file attribution, content-dependency re-verification, conflict disambiguation, and unpatterned advice approval.
B. Two-Tiered L2 Authority & Provisional Trial Period
Flightdeck splits agent-generated evidence into two distinct epistemic tiers:

L2b (Transcript Miner): Deterministic sequential inference (trust score: 0.70). Completely reproducible pattern matching over tool event trajectories.
L2a (Host Agent): Contextual LLM reasoning (trust score: 0.75). Non-deterministic judgment.
When $L2a$ and $L2b$ make contradictory assertions, neither silently overrides the other. The system marks the memory as CONFLICTED and generates a dual-claim directive presenting both perspectives to the developer.

The 7-Day Provisional Trial Window
To prevent bad LLM adjudications from permanently poisoning the graph:

Any host-agent-approved candidate enters active with a 7-day trial_until timestamp (is_provisional = true).
Retieved prompt directives flag it as ⚠️ [PROVISIONAL TRIAL].
If a compiler error or subsequent session contradicts the atom during its trial period, it is automatically demoted to pending_adjudication for human review rather than remaining active.
If it survives 7 days without contradiction, the background consolidation engine solidifies it into a permanent active rule.
C. Solving the Compliance Problem: SessionStart Hook Injection
Traditional memory tools suffer from the "agent forgets to call memory" problem. Flightdeck solves this deterministically at the hook layer:

In native Swift (

CLI.swift
), the SessionStart hook queries pending adjudications before the agent takes its first turn.
If pending items exist, Flightdeck injects a mandatory notice directly into the agent's startup stream:
text
⚠️ [FLIGHTDECK ACTION REQUIRED: 3 pending memory adjudication(s)]
> Call memory_pending_adjudication or run 'ecs pending' before proceeding.
Retrieval queries (

retrieval.py
) prepend this banner to directive blocks, converting memory review from an optional manual step into an unmissable workflow.
D. Git-Anchored Staleness & Drift Detection (Context Fabric)
Every memory capsule stores an anchor (

MemoryAnchor
):

filePath
symbolName (AST symbol / function / enum)
contentHash (SHA-256 of the referenced code snippet)
commitSha (Git commit where the fix was proven)
During retrieval, Flightdeck verifies the anchor against the working tree and Git HEAD:

verified: The content hash matches the committed code exactly.
stale: Code shifted or lines moved, but the AST symbol persists (applies a search ranking penalty).
contradicted: The referenced symbol was deleted or structurally rewritten. Contradicted memories are blocked on-demand from prompt injection.
missingSource: The target file was deleted.
E. Bitemporal Causal Graph & Blast Radius CTE
Memories in Flightdeck are bitemporal:

System Time (recorded_at, invalidated_by): When the memory was recorded or superseded by Flightdeck.
Valid Time (valid_from, valid_until, trial_until): When the assertion held true in the physical codebase.
Memory atoms connect via directed causal edges:

SOLVES: A fix resolving a specific failure trap.
CAUSES: A change that introduced a regression.
DEPENDS_ON: A rule requiring a specific dependency or architectural invariant.
CONTRADICTS: Mutually exclusive assertions competing for the same slot.
SUPERSEDES: A newer, higher-authority assertion invalidating an older rule.
Using a SQLite Recursive Common Table Expression (CTE), Flightdeck can compute the blast radius of any refactoring in $<2,\text{ms}$, warning agents of all transitive traps that may break if a file or symbol is modified.

F. Offline Consolidation: The Dream Phase
Adapted from the Khora biological sleep consolidation architecture, Flightdeck runs an offline maintenance loop (

dream.py
):

Phase 1 (Audit): Computes drift ratios, scans for orphaned causal edges, counts pending candidates, and flags contradiction pairs.
Phase 2 (Compaction with Hard Guardrails):
7-Day Retention Floor: Superseded tombstones younger than 7 days are strictly protected against deletion.
90-Day Conflict Aging Ceiling: Unresolved equal-authority conflicts older than 90 days are archived.
Provisional Promotion: Active provisional atoms whose 7-day trial expired without challenge have their provisional flags cleared.
Snapshot-Before-Delete: Automatically dumps an undo_dream_<timestamp>.json state backup before physical compaction.
3. Technology Stack & Performance
Component	Technology	Rationale
Native Daemon & CLI	Swift 6, GRDB, SQLite WAL	Zero-latency macOS native monitoring, memory safety, $<11,\text{MB}$ resident RAM.
Substrate & MCP Server	Python 3.13, FTS5 BM25, MCP SDK	Headless cross-platform portability, Porter stemmer lexical search, stdio MCP transport.
Storage Engine	SQLite in WAL mode with Foreign Keys & Triggers	Single-file embedded storage, atomic transactions, ACID durability, zero background daemon crashes.
Egress / Privacy	100% Local (0 cloud network calls)	Code snippets, error signatures, and Git paths never leave the developer's machine.
Speed	Sub-10ms (P50 6.41ms on 10k benchmark)	Fast-path conjunctive FTS5 queries with on-demand git diff checks.
Test Coverage	321 Swift tests (48 suites) + 26 Python tests	100% pass rate covering edge conditions, CTE traversal, drift recovery, git federation, and MCP tooling.
4. How It Works in Practice (End-to-End Walkthrough)
Session 1: The Trap is Discovered
Claude Code attempts to use .measured on ContextWindowSource in DevCleaner.swift.
Swift compiler fails: error: type 'ContextWindowSource' has no member 'measured'.
The developer or agent updates the code to use .inferred. The build passes (Exit Code 0).
Flightdeck captures the event trajectory and stores a candidate triple:
Trigger: .measured
Failure: type ContextWindowSource has no member 'measured'
Resolution: Valid cases are .statusline, .inferred, .fallback
Verified By: transcript_miner (Authority L2b)
Session 2: The Mistake is Prevented
A new agent session starts 2 hours later with a wiped context window.
The agent calls memory_context(project: "Flightdeck", file_paths: ["Sources/Flightdeck/DevCleaner.swift"]) via MCP (or runs ecs check).
Flightdeck retrieves the verified atom in $6,\text{ms}$ and injects:
markdown
### FLIGHTDECK CAUSAL MEMORY DIRECTIVES
> Verified hazard traps and proven rules for current context:
⚠️ TRAP: `Sources/Flightdeck/DevCleaner.swift` (symbol: `ContextWindowSource`)
  Trigger: .measured
  Failure: error: type ContextWindowSource has no member 'measured'
  Fix: Valid cases are .statusline, .inferred, .fallback
The agent reads the directive and writes .inferred on the first attempt without triggering a compiler break.
5. Beyond Memory: The Flightdeck macOS Ecosystem
In addition to the Epistemic Causal Substrate (ECS), Flightdeck includes a full suite of developer environment tools:

DevCleaner: Scans and cleans multi-gigabyte developer caches (Xcode DerivedData, Cargo registry caches, SPM artifacts, CocoaPods) without breaking active builds.
Zombie Process Detector: Identifies orphan LLM subagents, dead language servers, and orphaned simulator processes that consume RAM and CPU cycles.
Hardware & Battery Telemetry: Live SMC/IOKit monitoring of CPU/GPU temperatures, memory pressure, and Apple Silicon thermal throttling states.
Session Token Spend Ledger: Audits and reconciles Claude Code and Cursor token usage against model cost schedules to monitor developer spend.

6. Decentralized Git Federation & Team Sync (`.flightdeck/memory/`)
Flightdeck eliminates the need for centralized cloud memory servers by federating causal memory through native Git commits:
* **Plain-Text JSONL Storage**: Memory atoms and causal edges export to `.flightdeck/memory/atoms.jsonl` and `edges.jsonl`.
* **Zero Diff Noise**: Deterministic sort order `(filePath ASC, symbol ASC, triggerPattern ASC, id ASC)` ensures that concurrent additions produce clean, single-line diffs without reflow merge conflicts.
* **Write-Side Adjudication on Import**: Teammate memories imported via `flightdeck memory import` or `ecs import` pass through Gate 3 CUPMem slot adjudication; competing equal-authority claims automatically enter `CONFLICTED` status rather than blindly overwriting local memory.
* **Automated Git Hooks**: `flightdeck memory install-git-hooks` installs lightweight `.git/hooks/post-merge` and `post-checkout` hooks to keep the local SQLite substrate continuously synchronized with incoming Git pulls.