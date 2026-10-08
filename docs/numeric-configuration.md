# Numeric configuration validation

## Purpose

Reject unsafe numeric settings before the active baseline can begin a run, while the configuration schema is still migrating.

## Implemented behavior

`src.config.numeric_validation.validate(config)` accepts either the active baseline field names or the corresponding nested plan schema fields. It checks positive integer floor, stair-step, branch-count, and branch-length values; branch spacing of at least two; inventory thresholds from 1 through 15; and non-negative integer fuel reserves, supply targets, and item quotas. If `mining.stairStepsPerFloor` is supplied, it must equal 8 for V1. The schema field remains available for future configuration and testing; omission remains valid while the active baseline has no staircase configuration. Validation runs before the start prompt and before any turtle movement.

## Invariants and assumptions

- Validation is pure and performs no turtle action or inventory operation.
- Missing optional fields are allowed while the runtime config is migrated; configured values must satisfy their range and the fixed V1 stair count.
- Configuration validation is independent of movement, inventory, and persistence modules.

## Dependencies and limitations

The validator uses only Lua tables, `math.floor`, and `math.huge`. It does not yet enforce the separate fixed surface-entry, stair-width/height, turn, or tunnel-height rules.

The deterministic test is `tests/numeric_validation.lua`; it covers acceptance of eight and rejection of other positive stair counts. It passed with the configured Lua runtime, as did `luac.exe -p` for the changed Lua files. No in-world verification was performed.
