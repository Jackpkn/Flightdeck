# Flightdeck Epistemic Causal Substrate Guidelines

When working inside this repository:

1. **Check Hazards Before Refactoring Core Files**:
   Before modifying core data structures or system components (such as `ActivityDatabase.swift`, `CausalMemory.swift`, `DevCleaner.swift`, or SQLite queries), consult the causal memory layer using `memory_context` (via MCP) or `flightdeck memory check <path>` to avoid known compiler pitfalls and regressions.

2. **Record Reusable Traps and Fixes**:
   When diagnosing and fixing non-obvious compiler errors, race conditions, or architecture constraints, persist a micro-directive using `memory_store` (via MCP) with:
   - `kind`: `trap` or `invariant`
   - `trigger_pattern`: The exact syntax or symbol pattern causing failure
   - `failure_mode`: The compiler error or crash signature
   - `resolution`: The verified solution

3. **Honor Bitemporal Invalidation**:
   If an edit invalidates a prior architectural assumption, update or supersede the relevant memory capsule so dependent nodes are updated through topological propagation.
