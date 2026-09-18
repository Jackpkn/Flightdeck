---
name: flightdeck-memory
description: >-
  Consults and records causal memories, hazard traps, and architectural invariants in the
  Flightdeck Epistemic Causal Substrate (ECS). Use when preparing to edit sensitive source files,
  debugging compilation or runtime errors, or recording discovered pitfalls and architectural fixes.
---

# Flightdeck Epistemic Causal Substrate (ECS) Skill

This skill interfaces with the Flightdeck Epistemic Causal Substrate (ECS) via Model Context Protocol (MCP) tools or the local command-line engine.

## Available MCP Tools

* **`memory_context(query, project, file_path, budget_tokens)`**:
  Queries the causal memory layer for micro-directive hazard warnings, trigger patterns, and resolutions before editing or refactoring code.
* **`memory_store(project, claim, file_path, symbols, kind, authority_level, trigger_pattern, failure_mode, resolution, causal_links)`**:
  Records discovered pitfalls, compiler traps, or architectural invariants into the bitemporal substrate.
* **`memory_reverify(project, repo_path)`**:
  Re-verifies cached code claims against committed Git repository blobs using hash-anchored AST symbol checking.
* **`memory_status(project)`**:
  Reports active capsules, tombstone counts, and physical database metrics.
* **`memory_dream(project, apply)`**:
  Runs the offline consolidation sweep with retention floors.
* **`memory_pending_adjudication(project)`**:
  Lists candidate memories queued in `pending_adjudication` waiting for Gate 4 host-agent disambiguation.
* **`memory_adjudicate(candidate_id, decision, reason, host_agent, target_file)`**:
  Gate 4 Host Agent Adjudication: Resolves multi-file attribution (`decision='attribute'`), content-dependency validity (`decision='valid'|'stale'`), UNKNOWN conflicts (`decision='distinct_scope'|'resolve_conflict'`), or unpatterned advice validation (`decision='validate_advice'`).

## CLI Equivalent Commands

You can also inspect or verify memories directly in the terminal:
```bash
# Check hazard traps for specific files
flightdeck memory check Sources/Flightdeck/DevCleaner.swift
# Or via ecs CLI
ecs check Sources/Flightdeck/DevCleaner.swift

# List pending candidate adjudications (Gate 4)
ecs pending

# Adjudicate a candidate
ecs adjudicate <candidate_id> validate_advice --reason "Specific parameter ordering fix"

# List all recorded memory capsules
flightdeck memory list
```
