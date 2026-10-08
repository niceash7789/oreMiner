# Numeric configuration validation

## Purpose

Reject unsafe numeric settings before the active baseline can begin a run, while the configuration schema is still migrating.

## Implemented behavior

`src.config.numeric_validation.validate(config)` accepts either the active baseline field names or the corresponding nested plan schema fields. It checks positive integer floor, stair-step, branch-count, and branch-length values; branch spacing of at least two; inventory thresholds from 1 through 15; and non-negative integer fuel reserves, supply targets, and item quotas. The active CLI retries non-whole-number entries and validates the assembled settings before presenting the start prompt.

## Invariants and assumptions

- Validation is pure and performs no turtle action or inventory operation.
- Missing optional fields are allowed while the runtime config is migrated; configured values must satisfy their range.
- Configuration validation is independent of movement, inventory, and persistence modules.

## Dependencies and limitations

The validator uses only Lua tables, `math.floor`, and `math.huge`. It covers the numeric fields named by the current configuration plan and active baseline; it does not enforce the separate fixed-geometry rules in the next checklist items.

The deterministic test is `tests/numeric_validation.lua`. It passed with the configured Lua runtime, as did `luac.exe -p` for the changed Lua files. No in-world verification was performed.
