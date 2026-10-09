# Local progress persistence

## Purpose

Keep the active single-turtle run's committed pose and traversed route durable, and stop safely when a restart cannot prove the turtle's physical pose.

## Implemented behavior

`src/persistence/state.lua` validates schema version 1 snapshots, allowed status/certainty/action enums, finite integer coordinates and config values, and the route graph's coordinate keys, adjacency, reversibility, home, and current-pose membership. It writes a temporary snapshot, validates it after writing, rotates a valid active snapshot to `.bak`, and then commits the temporary file. Loads fall back to a valid backup, reject invalid expected configuration and mismatched saved configuration, and report `POSITION_UNCERTAIN` when a movement/turn intent remains pending. If neither the active nor backup snapshot validates, `State.load` returns `STATE_CORRUPT`; it returns `STATE_MISSING` only when both files are absent, the sole condition that permits starting a new run. The coordinator stops on corruption before prompting or initializing a run. A leftover `.tmp` file is not considered by `State.load`; interrupted-write recovery from that file is not implemented. `src/persistence/checkpoint.lua` owns run-state creation/loading and the durable checkpoint lifecycle: snapshotting the live pose/route/config, saving pending action intent, committing or cancelling an action, and recording fatal/complete status. Error-status snapshots require a string error code. When mining reports failure, the coordinator synchronously calls `markFatal` to save the error status and code before `main` returns. The coordinator keeps its live pose and route in memory and passes them to this boundary; it does not mutate the encoded state record. Startup also refuses to overwrite incompatible state and refuses to restart an incomplete run because the mining resume cursor is not yet implemented.

The active movement/turn wrappers in `src/branch_miner.lua` persist a typed `pendingAction` before invoking the turtle API. On literal success they install the returned pose (and movement route edge) and immediately save it with the pending action cleared. On API failure they retain the old pose and cancel the intent; a failed post-action save stops execution and leaves the previous durable pending intent to force `POSITION_UNCERTAIN` on reboot.

`src/mining/cursor.lua` defines validated logical cursors for the active baseline and route preparation. Baseline cursors record a stable work-unit ID, floor `0`, branch pair, side, phase, local offset, main offset, and next action. `Cursor.stairs(floor, step, action)` describes surface entry, a bounded stair slice, or landing preparation with a stable floor/stair segment identity. The active baseline coordinator saves its cursor through `Checkpoint.setProgress` before each bounded main-shaft cell, junction turn, branch outbound cell, turnaround, and lower or upper return cell. Stair cursors are a validated contract for the pending S02 coordinator integration; they are not yet emitted by the active coordinator. A rejected or failed cursor save stops the coordinator before that unit begins and retains the previous in-memory cursor. Physical-action intent snapshots therefore carry the logical unit that issued the move or turn once route wiring is complete.

Snapshots optionally contain `floorLandings`, keyed by floor number. Each record stores the segment origin, mouth, rear-centre, landing-centre, step count, and entry length. Validation checks the geometric displacement, contiguous floor-to-floor origins, and that route landmarks exist in the recorded known-route graph. `Session.recordFloorLanding` persists a validated record with the current pose/graph; `floorLanding(floor)` and `floorLandings()` return defensive copies. Older snapshots without this optional field remain valid.

This satisfies persistence checklist item P01: the serializer output is written and closed at `.tmp`, decoded and schema-validated from disk, then installed after rotating the validated active file to `.bak`. P01 does not cover promotion of a leftover `.tmp` after a crash; that recovery remains separate work.

Only the current coordinator's minimal persistent data is stored: run ID/status, committed pose, known-route graph, small baseline progress descriptor, pending action, and job-affecting configuration snapshot. Scratch caches, logs, and statistics are excluded.

## Public entry points

- `require("src.mining.cursor")` provides `initial`, `mainShaft`, `junction`, `branch`, `stairs`, and `validate`.
- `State.new(configSnapshot, pose, route, runId)`
- `State.validate(state)`
- `State.save(state, path, fsApi, textutilsApi)`
- `State.load(path, expectedConfig, fsApi, textutilsApi)`
- `Checkpoint.create(configSnapshot, pose, route, runId, path, fsApi, textutilsApi)`
- `Checkpoint.load(path, expectedConfig, fsApi, textutilsApi)`
- Session methods: `save`, `setProgress`, `recordFloorLanding`, `floorLanding`, `floorLandings`, `beginAction`, `commitAction`, `cancelAction`, `markFatal`, `markComplete`, and `status`.

## Invariants and assumptions

- Only literal successful turtle moves/turns advance the durable pose.
- Any persisted pending action is ambiguous after reboot; callers must stop with `POSITION_UNCERTAIN` before movement.
- State files are local to the turtle and use CC:Tweaked `fs` and `textutils` APIs.
- The saved configuration fields must match before loading a run.
- A route snapshot contains the home and current pose as graph nodes; every recorded edge is between adjacent coordinate keys and has a reverse edge.
- The live state machine owns pose/route updates; checkpoint methods copy those values into the durable snapshot at each write.
- `progress.nextAction` names work that has not yet begun; a cursor is persisted before its bounded unit invokes service, digging, movement, or turning.

## Dependencies and limitations

The module depends on injected CC:Tweaked-compatible filesystem and text serialization APIs. Stair route records are now durable building blocks, but the logical cursor still covers only the current surface-level baseline (`floor = 0`); stair/floor phase resume, service state, vein frontier state, cursor-driven execution, and automatic restart remain incomplete. Startup therefore still refuses to resume an incomplete run. Snapshots from an earlier development version that contain only the old generic `active_baseline / continue` marker fail validation rather than being treated as resumable. Unexpected Lua exceptions escaping the coordinator are not intercepted. Manual in-world power-loss testing has not been performed.

## Verification

`tests/mining_cursor.lua` covers cursor construction, phase/action agreement, and rejection of incomplete or invalid cursors. `tests/persistence_state.lua` also verifies two geometrically consistent saved floor routes, reload, and rejection of inconsistent landing geometry. Existing codec, backup, pending-action, cursor, and fatal-state checks remain covered. It does not yet test recovery from a leftover `.tmp` snapshot. `tests/active_baseline_wiring.lua` verifies that physical actions observe both their durable intent and a durable logical cursor.
