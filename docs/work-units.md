# Sequential work-unit checkpoints

## Purpose

Give each persisted next action enough identity and route context to report, validate, and resume it safely while the V1 executor remains one sequential turtle.

## Implemented behavior

Mining cursors name the `shaft` or `floor` domain and retain their phase-specific cursor fields. Persisted vein excursions identify the `ore` domain; inventory trips identify `service`. Each active cursor includes its work-unit ID, committed origin pose, fixed outbound heading, configured route bounds, cursor, and completion status. Return cursors keep the original outbound heading even while the turtle faces homeward. The terminal unit is marked complete with the run.

## Public entry points

- `require("src.mining.cursor").withWorkUnit(progress, origin, config)` frames a validated cursor at a committed checkpoint.
- `Checkpoint` sessions persist framed progress through `setProgress`, `setService`, and vein lifecycle methods.
- `State.validate` checks metadata bounds and rejects a descriptor inconsistent with its cursor or configured route.

## Invariants and assumptions

- Origin and cursor are saved in one snapshot; movement intent still follows the pending-action protocol.
- Frame headings use the route's outbound direction, including upper-return and junction-return phases.
- Bounds are derived from the validated job configuration and allow the stair `steps + 1` landing-preparation cursor.
- Existing schema-1 snapshots without optional work-unit metadata remain readable.

## Dependencies and limitations

The work-unit descriptor depends on `src/mining/cursor.lua` and the checkpoint/state codec. It records the current/terminal unit rather than an unbounded execution history; completed intermediate units are represented by the next committed cursor. Physical resume and route geometry still require the documented controlled-gallery checks.

## Verification

`tests/persistence_state.lua`, `tests/persistence_recovery.lua`, and `tests/active_baseline_wiring.lua` cover metadata validation, restart snapshots, and the active coordinator. Lua syntax checks cover the changed modules and tests.
