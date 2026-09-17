# Flightdeck Epistemic Causal Substrate (ECS)
### Next-Generation Deterministic Shared Memory for Autonomous Coding Agents

> **Thesis**: Traditional Vector RAG and generic cloud memory layers (e.g. Mem0) fail software engineering agents because they are **causally blind, semantically fuzzy, and structurally detached from the code graph**. Flightdeck ECS replaces vector similarity with a **local, deterministic, file-anchored causal execution substrate** versioned by Git.

---

## 1. Executive Summary & Problem Space

### Why Vector RAG Fails Coding Agents
Vector databases compute cosine distance over embedding vectors derived from unstructured chunks of natural language text. In software engineering, this produces fundamental failure modes:
1. **Semantic Similarity $\neq$ Causal Correctness**: Two code snippets can be 98% semantically identical while one contains a fatal compiler bug and the other is valid. Vector RAG cannot distinguish causal correctness from prose similarity.
2. **Token Bloat & Context Decay**: RAG pipelines dump paragraphs of conversational context into the agent's prompt (often 1,500–4,000 tokens), degrading the LLM's instruction attention and accelerating context window exhaustion.
3. **Stale Memory Poisoning**: As code evolves, vector stores retain outdated representations. An agent querying a months-old chunk receives instructions for functions or configurations that no longer exist, leading to hallucinations.

### Why Mem0 & Cloud Middleware Fail
1. **Zero-Cloud Privacy Violations**: Enterprise and security-conscious developers refuse to route proprietary source code, shell commands, and API interactions to third-party cloud memory platforms.
2. **High Latency Overhead**: Cloud memory roundtrips inject 300ms–800ms of latency into every agent turn.
3. **No Code Graph or Toolchain Awareness**: Generic cloud memory layers have no awareness of compilers (`swiftc`, `cargo`, `tsc`), test runners, AST symbols, or Git commit histories.

---

## 2. The Four Pillars of Flightdeck ECS

```
┌────────────────────────────────────────────────────────────────────────┐
│                   FLIGHTDECK COCKPIT DECK (GUI)                        │
│   ┌────────────────────────────────────────────────────────────────┐   │
│   │ [Traps: 3 Active] · [Proven Rules: 14] · [Causal Graph Viewer] │   │
│   └────────────────────────────────────────────────────────────────┘   │
└───────────────────────────────────▲────────────────────────────────────┘
                                    │ (0.1ms Local SQLite Query)
┌───────────────────────────────────┴────────────────────────────────────┐
│      Flightdeck Epistemic Causal Substrate (Native Swift + SQLite)     │
│                                                                        │
│  1. CAUSAL VERIFICATION TRIPLES (Hypothesis ➔ Compiler/Test ➔ Verdict) │
│  2. STIGMERGIC HAZARD TRAPS (Deterministic File & AST Anchoring)       │
│  3. GIT-VERSIONED TRUTH INVALIDATION (Zero Stale Memory Drift)         │
│  4. MICRO-CAPSULE ENCODING (<60 Tokens Per Rule, No Context Waste)     │
└───────────────────▲────────────────────────────────▲───────────────────┘
                    │                                │
            (Local JSON-RPC)                 (Local CLI Pipes)
┌───────────────────┴───────────────┐    ┌───────────┴───────────────────┐
│   Claude Code Session 1           │    │   Claude Code Session 2       │
│  (Fails compiler on enum case,    │    │  (Reads trap BEFORE editing,  │
│   stores causal fix into local DB)│    │   skips mistake completely)   │
└───────────────────────────────────┘    └───────────────────────────────┘
```

### Pillar 1: Causal Execution Triples
Software engineering is empirical cause-and-effect. Flightdeck ECS models memory as formal empirical tuples rather than prose embeddings:

$$\text{Memory Capsule} = \langle \text{Scope / File}, \text{Causal Trigger}, \text{Observed Failure}, \text{Proven Fix}, \text{Git SHA} \rangle$$

* **Scope**: The exact canonical file path and symbol (e.g. `Sources/Flightdeck/CLI.swift` / `handleSessions`).
* **Causal Trigger**: The command, syntax pattern, or parameter that prompted the state transition.
* **Observed Failure**: The compiler diagnostic, test failure message, or exit code.
* **Proven Fix**: The verified resolution that successfully compiled and passed tests.
* **Git SHA**: The tree state where this causal relationship was verified.

### Pillar 2: Stigmergic Code Anchoring
In biological stigmergy, social insects coordinate not through direct communication, but by leaving localized physical markers (pheromones) on the environment.
* **Negative Pheromones (Hazard Traps)**: If Session 1 attempts an edit on line 84 of `DevCleaner.swift` that triggers an invalid enum error or breaks unit tests, Flightdeck places a **Deterministic Hazard Marker** on that file in local storage.
* When Session 2 (or a concurrent agent) touches `DevCleaner.swift`, Flightdeck delivers an immediate micro-attunement:
  > `⚠️ HAZARD (DevCleaner.swift): Using .measured on ContextWindowSource fails compilation. Valid cases are .statusline, .inferred, .fallback.`
* **Zero guesswork, zero vector search uncertainty**—memory is deterministically addressed by repository coordinates.

### Pillar 3: Git-Versioned Truth Invalidation
To solve the "stale memory" problem that plagues vector stores:
* Every capsule records the `git rev-parse HEAD` commit and file content hash at the time of verification.
* When files are modified in subsequent commits, Flightdeck compares current Git tree state against capsule metadata:
  * **Unchanged**: State remains `ACTIVE` (100% confidence).
  * **Modified in Tree**: State transitions to `NEEDS_REVERIFICATION`.
  * **Deleted / Renamed**: State transitions to `OBSOLETE` or maps to the new path via Git rename tracking.

### Pillar 4: Micro-Capsule Token Density (<60 Tokens)
Standard RAG systems dump thousands of tokens into prompt context. Flightdeck compiles causal triples into ultra-dense, syntax-highlighted directives:

```markdown
[FLIGHTDECK MEMORY: Sources/Flightdeck/DevCleaner.swift]
- TRAP: Cargo registry requires cache in ~/.cargo/registry/cache (not ~/.cargo/cache).
- RULE: Run DevCleanerTests before committing any directory count logic.
```
**Total footprint**: ~45 tokens. Zero context pollution; 100% actionable signal.

---

## 3. Database Schema (Native SQLite & GRDB)

Flightdeck ECS persists locally in `~/.flightdeck/activity.db` alongside existing session telemetry:

```sql
-- 1. Persistent Causal Memory Capsules
CREATE TABLE memory_capsules (
    id TEXT PRIMARY KEY NOT NULL,
    project TEXT NOT NULL,
    file_path TEXT NOT NULL,
    symbol TEXT,
    kind TEXT NOT NULL, -- 'trap', 'rule', 'invariant', 'dead_end'
    trigger_pattern TEXT NOT NULL,
    failure_signature TEXT,
    resolution TEXT NOT NULL,
    origin_session_id TEXT,
    git_sha TEXT NOT NULL,
    file_hash TEXT,
    confidence REAL NOT NULL DEFAULT 1.0,
    hit_count INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'active', -- 'active', 'unverified', 'obsolete'
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL
);

CREATE INDEX idx_memory_project_path ON memory_capsules(project, file_path);
CREATE INDEX idx_memory_status ON memory_capsules(status);

-- 2. Stigmergic Observations (Pheromone Trails)
CREATE TABLE memory_observations (
    id TEXT PRIMARY KEY NOT NULL,
    capsule_id TEXT NOT NULL REFERENCES memory_capsules(id) ON DELETE CASCADE,
    session_id TEXT NOT NULL,
    outcome TEXT NOT NULL, -- 'prevented_failure', 'verified_success', 'stale_refuted'
    observed_at DATETIME NOT NULL
);
```

---

## 4. Developer & Agent Integration Interfaces

### Interface A: Flightdeck Memory CLI
Developers and shell scripts can interact directly with the substrate:

```bash
# List active memory traps and proven rules for current repo:
flightdeck memory

# Check hazards and invariants for specific files:
flightdeck memory check Sources/Flightdeck/CLI.swift

# Explicitly register a verified rule or trap:
flightdeck memory trap \
  --file "Sources/Flightdeck/DevCleaner.swift" \
  --trigger "rm -rf ~/.cargo/cache" \
  --fix "Cargo cache is located at ~/.cargo/registry/cache"

# Prune obsolete or low-confidence capsules:
flightdeck memory prune --reverify-git
```

### Interface B: Local Model Context Protocol (MCP) Server
Flightdeck exposes native MCP tools to Claude Code and other agent runners via `flightdeck mcp`:

```json
{
  "name": "flightdeck_check_hazards",
  "description": "Checks Flightdeck's local deterministic memory for known failure traps, compiler gotchas, and invariants for files about to be modified.",
  "parameters": {
    "type": "object",
    "properties": {
      "file_paths": {
        "type": "array",
        "items": { "type": "string" },
        "description": "List of relative file paths the agent intends to edit or inspect"
      }
    },
    "required": ["file_paths"]
  }
}
```

```json
{
  "name": "flightdeck_record_causal_rule",
  "description": "Records a verified cause-and-effect learning (such as a compiler fix, tool quirk, or invariant) into Flightdeck's persistent repository memory.",
  "parameters": {
    "type": "object",
    "properties": {
      "file_path": { "type": "string" },
      "trigger": { "type": "string" },
      "failure": { "type": "string" },
      "resolution": { "type": "string" }
    },
    "required": ["file_path", "trigger", "resolution"]
  }
}
```

---

## 5. Cockpit Deck UI: Stigmergy & Memory Inspector

Within Flightdeck's macOS Cockpit HUD:
1. **Visual Hazard Sentinel**:
   - Files with active traps display an amber badge in the File Browser (`⚠️ 2 Traps`).
   - Clicking reveals the exact failure signatures and proven fixes recorded by earlier sessions.
2. **Causal Knowledge Graph**:
   - Interactive node graph showing relationships: `File ➔ Compiler Error ➔ Proven Fix ➔ Commits in HEAD`.
3. **1-Click Export to `CLAUDE.md` / Rules**:
   - Compiles all active, high-confidence memory capsules directly into clean markdown rules for project initialization.

---

## 6. Implementation Roadmap

| Phase | Milestone | Deliverables |
| :--- | :--- | :--- |
| **Phase 1: Substrate Core** | Data Model & SQLite Engine | `MemoryCapsule` models, GRDB migrations, Git SHA stamping, and unit tests. |
| **Phase 2: CLI Interface** | Terminal Tooling | `flightdeck memory`, `flightdeck memory check`, `flightdeck memory trap`. |
| **Phase 3: Automatic Ingestion** | Transcript Causal Miner | Background analyzer parsing transcripts for `tool_error` ➔ subsequent fix loops. |
| **Phase 4: MCP Protocol** | Zero-Latency Agent Tools | `flightdeck_check_hazards` & `flightdeck_record_causal_rule` in Flightdeck MCP Hub. |
| **Phase 5: Cockpit HUD** | Visual Stigmergy Deck | Live hazard map, capsule audit inspector, and 1-click rule synchronization. |

---

*Authored for Flightdeck — Zero-Cloud macOS Cockpit & Activity Monitor for AI Coding Agents.*
