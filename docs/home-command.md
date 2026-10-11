# Operator home command

## Purpose

Let an operator stop a saved mining job at a known checkpoint and send the turtle to surface origin.

## Implemented behavior

Run `miner home` from the turtle shell after the mining program has stopped and returned to the prompt. The command loads the saved run, immediately marks it paused, unwinds a saved ore-vein excursion through its inverse breadcrumbs, then follows the durable home breadcrumb one checked cell at a time. The breadcrumb is a loop-erased list of actual successful moves from origin to the current absolute pose. Each successful movement updates both the pose and breadcrumb in the same checkpoint. It does not ask for confirmation or continue mining. At base it stores a service checkpoint so `miner resume` can unload/resupply and return to the exact saved work cursor. If power is lost during travel, each successful physical action remains checkpointed; a pending action remains uncertain and is refused.

Ctrl+T during an active `miner` or `miner resume` run now requests a graceful stop. The launcher holds the termination event while a turtle API call completes; the coordinator then stops before the next movement, turn, or checkpointed physical action. The launcher runs the same checked `miner home` path before returning to the shell. `miner home` remains available at the prompt for a run that has already stopped. A Ctrl+T during `miner home`, `miner status`, or another command is not converted into another home attempt. The command still enforces known-pose, recorded-route, and per-move fuel safety requirements.

## Public entry points

- `miner home` dispatches in `src/branch_miner.lua`.
- `miner.lua` supervises active mining and calls `home` after a stop request; `src/safety/exit_home.lua` holds the Ctrl+T event and reports home errors.
- `src/branch_miner.lua` checks the request before starting a movement, turn, or checkpointed physical action, and while waiting for supplies at base.
- `Session.markPaused(pose, route, configSnapshot)` persists a resumable paused run in `src/persistence/checkpoint.lua`.
- `Session.markMining(pose, route, configSnapshot)` returns a paused run to active status before resume travel begins.
- `Session.setService(service, pose, route, configSnapshot)` records return-to-base and parked-at-base recovery stages.
- `Recovery.classify(state, loadCode)` admits known paused snapshots through the existing route and cursor recovery rules.

## Invariants and assumptions

- The command follows the saved breadcrumb's recorded edges and never creates a shortcut. The shared checked movement adapter may dig a block obstructing the next recorded cell, subject to inventory and bounded retry limits. Older valid snapshots without a breadcrumb use the recorded graph.
- Saved pose certainty must be `known` and there must be no pending physical action before departure.
- A saved vein is unwound before ordinary route travel begins.
- The paused service record preserves the exact mining cursor, allowing `miner resume` to return to that job after base service.
- Every movement still passes the route-home fuel policy, including the proposed move's own fuel cost, and durable intent/commit sequence.

## Dependencies and limitations

Requires the existing local state snapshot, CC:Tweaked filesystem and serialization APIs, a known pose, and a recorded return route. Coordinates are absolute relative to the fixed surface origin, not GPS world coordinates. The graceful path needs the computer to keep running long enough for the current action to finish and for the return trip; closing Minecraft or powering off the computer cannot run a turtle after shutdown. If a physical action never returns or the saved pending action predates this run, `home` refuses to move and reports `POSITION_UNCERTAIN`. An uncleared block, inadequate fuel, inventory pressure, uncertain pose, or persistence failure stops the command at the last committed checkpoint. Software cannot guarantee a physical return across an unconfirmed movement or turn.

## Verification

`tests/recovery_status.lua` covers command dispatch without a confirmation prompt and verifies that a home command at base leaves a paused service checkpoint. `tests/home_breadcrumb.lua` covers per-move pose/trail updates, loop removal, blocked return, exact home replay, and invalid persisted breadcrumbs. `tests/persistence_state.lua` covers paused-state roundtrip and recovery admission. In-world return geometry and interrupted return recovery still require operator verification.

`tests/miner_entrypoint.lua` covers Ctrl+T dispatch from mining and resume, a pending action finishing before home, and verifies that read-only commands do not dispatch home. `tests/exit_home.lua` covers event filtering, termination recognition, and reporting if home raises an error. Ctrl+T during a physical action and a complete return still need a backed-up-world check.
