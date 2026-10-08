# Numeric configuration validation

## Purpose

Reject unsafe numeric settings before the active baseline can begin a run, while the configuration schema is still migrating.

## Implemented behavior

`src.config.numeric_validation.validate(config)` accepts either the active baseline field names or the corresponding nested plan schema fields. It checks positive integer floor, stair-step, branch-count, and branch-length values; branch spacing of at least two; inventory thresholds from 1 through 15; and non-negative integer fuel reserves, supply targets, and item quotas. Supplied V1 route geometry fields must be `mining.stairStepsPerFloor = 8`, `mining.surfaceEntryLength = 4`, `mining.stairWidth = 3`, `mining.stairHeight = 3`, and `mining.floorMainTurn = "right"`. These schema fields remain available for later configuration, but unsupported supplied values are rejected; omission remains valid while the active baseline has no staircase configuration. Validation runs before the start prompt and before any turtle movement.

## Invariants and assumptions

- Validation is pure and performs no turtle action or inventory operation.
- Missing optional fields are allowed while the runtime config is migrated; supplied stair geometry and floor-main turn must match the fixed V1 values exactly.
- Configuration validation is independent of movement, inventory, and persistence modules.

## Dependencies and limitations

The validator uses only Lua tables, `math.floor`, and `math.huge`. It does not yet enforce the supply/output chest sides, lighting side, or tunnel-height rule.

The deterministic test is `tests/numeric_validation.lua`; it covers accepted fixed geometry and right floor-main turn, and rejection of unsupported supplied geometry and turns. No in-world verification is performed by this check.
