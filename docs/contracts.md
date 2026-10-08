# Core contracts

## Purpose and behavior

Provide dependency-light validation for the single-turtle pose, persisted run status, work domain, currently specified phase labels, pose certainty, structured outcomes, and stable fatal codes. Validation is pure and does not mutate caller state.

## Public API

- `require("src.core.contracts")` exposes `FACING`, `RUN_STATUSES`, `WORK_DOMAINS`, `PHASES`, `POSE_CERTAINTIES`, and `ERROR_CODES`.
- `isPose(pose)` accepts integer `{x, y, z, facing}` with facing `0..3`.
- `isRunStatus`, `isWorkDomain`, `isPhase`, and `isPoseCertainty` validate their corresponding values.
- `isResult(result)` checks `{ok, code, message?, retryable?}`; domain-specific result codes are allowed.
- `isFatalCode(code)` identifies the stable fatal codes from the plan.

## Invariants and assumptions

- Coordinates are local integer block coordinates; facing is north/east/south/west as `0/1/2/3`.
- A saved pose is the last committed physical pose. Pose changes only after a literal successful movement/turn; a pending action makes automatic movement unsafe and must resolve to `POSITION_UNCERTAIN` after restart.
- Persisted run status is separate from work domain. V1 remains a single sequential executor.
- Phase labels cover the active baseline's main-shaft, junction, branch outbound, turnaround, lower/upper return, and junction-return cursor phases; add staircase and service labels with their planned implementations.

## Dependencies and limitations

Pure Lua; no turtle or filesystem dependency. `src/persistence/state.lua` validates the narrower phase/action combinations represented by `src/mining/cursor.lua`; full persistence/state-machine integration remains incomplete. This module does not execute movement or commit state.

## Verification

Run `lua tests/contracts.lua` for pose, result, enum, certainty, and fatal-code checks.
