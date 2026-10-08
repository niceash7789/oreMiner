# Numeric configuration validation

## Purpose

Reject unsafe numeric settings before the active baseline can begin a run, while the configuration schema is still migrating.

## Implemented behavior

`src.config.numeric_validation.validate(config)` accepts either the active baseline field names or the corresponding nested plan schema fields. It checks positive integer floor, stair-step, branch-count, and branch-length values; branch spacing of at least two; inventory thresholds from 1 through 15; and non-negative integer fuel reserves, supply targets, and item quotas. Supplied V1 route geometry fields must be `mining.stairStepsPerFloor = 8`, `mining.surfaceEntryLength = 4`, `mining.stairWidth = 3`, `mining.stairHeight = 3`, `mining.tunnelHeight = 2`, and `mining.floorMainTurn = "right"`. Supplied `base.supply`, `base.primaryOutput`, and `base.bulkOutput` sides must be `left`, `right`, and `back`, respectively. Supplied `lighting.side` must be `right`; this names the planned outbound route's right-hand side. These schema fields remain available for later configuration, but unsupported supplied values are rejected; omission remains valid while the active baseline has no configuration for those features. Validation runs before the start prompt and before any turtle movement.

## Invariants and assumptions

- Validation is pure and performs no turtle action or inventory operation.
- Missing optional fields are allowed while the runtime config is migrated; supplied stair geometry, tunnel height, floor-main turn, chest sides, and lighting side must match the fixed V1 values exactly. Tunnel-height validation does not change runtime geometry. Lighting-side validation does not implement torch placement.
- Configuration validation is independent of movement, inventory, and persistence modules.

## Dependencies and limitations

The validator uses only Lua tables, `math.floor`, and `math.huge`. It does not implement tunnel traversal or support configurable tunnel geometry.

The deterministic test is `tests/numeric_validation.lua`; it covers accepted fixed geometry including tunnel height 2, right floor-main turn and lighting side, canonical base chest sides, and rejection of unsupported supplied values. No in-world verification is performed by this check.
