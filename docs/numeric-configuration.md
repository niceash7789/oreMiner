# Numeric configuration validation

## Purpose

Reject unsafe numeric settings before the active baseline can begin a run, while the configuration schema is still migrating.

## Implemented behavior

`src.config.numeric_validation.validate(config)` accepts either the active baseline field names or the corresponding nested plan schema fields. It checks positive integer floor, stair-step, branch-count, and branch-length values; branch spacing of at least two; inventory thresholds from 1 through 15; and non-negative integer fuel reserves, supply targets, and item quotas. Supplied V1 geometry fields must be `mining.stairStepsPerFloor = 8`, `mining.surfaceEntryLength = 4`, `mining.stairWidth = 3`, and `mining.stairHeight = 3`. These schema fields remain configurable; omission remains valid while the active baseline has no staircase configuration. Validation runs before the start prompt and before any turtle movement.

## Invariants and assumptions

- Validation is pure and performs no turtle action or inventory operation.
- Missing optional fields are allowed while the runtime config is migrated; supplied stair geometry must match the fixed V1 dimensions exactly.
- Configuration validation is independent of movement, inventory, and persistence modules.

## Dependencies and limitations

The validator uses only Lua tables, `math.floor`, and `math.huge`. It does not yet enforce the separate fixed turn or tunnel-height rules.

The deterministic test is `tests/numeric_validation.lua`; it covers accepted fixed geometry and rejection of unsupported surface-entry lengths and stair widths/heights, as well as the fixed stair-step count. No in-world verification is performed by this check.
