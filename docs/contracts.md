# Core contracts

## Purpose and behavior

Define shared, dependency-light shapes for single-turtle poses, work domains, structured outcomes, and fatal error codes. The module validates rather than mutates caller state. The complete run-status and phase enums from the plan are not yet defined.

## Public API

- `require("src.core.contracts").isPose(pose)` checks integer `{x, y, z, facing}` with facing in `0..3`.
- `isResult(result)` checks the common `{ok, code, message?, retryable?}` outcome shape.
- `isFatalCode(code)` identifies the stable fatal codes listed by the plan.
- `FACING`, `WORK_DOMAINS`, `RUN_STATUSES`, and `ERROR_CODES` expose the shared constants.

## Invariants and assumptions

- Coordinates are local integer block coordinates; facing is north/east/south/west as `0/1/2/3`.
- Persisted run status is distinct from work domain. The shared work domains are `shaft`, `floor`, `ore`, and `service`; explicit phase values remain to be defined from the plan's saved-state contract.
- Physical pose changes only after literal turtle API success; this module validates the pose contract but does not execute or commit movement.
- A result's `ok` is boolean and its code is a non-empty string. Domain-specific result codes remain allowed.

## Dependencies and limitations

Pure Lua with no turtle or filesystem dependency. Pose, result, work-domain, and fatal-code contracts are available for gradual adoption; this partial item does not rewrite existing modules to use them or validate full persisted progress records. Run-status and phase constants remain an open requirement.

## Verification

Run `lua tests/contracts.lua` for pose, result, phase, and fatal-code checks.
