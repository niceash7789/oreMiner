# Operator home command

## Purpose

Let an operator stop a saved mining job at a known checkpoint and send the turtle to surface origin.

## Implemented behavior

Run `miner home` from the turtle shell after the mining program has stopped and returned to the prompt. The command loads the saved run, immediately marks it paused, unwinds a saved ore-vein excursion through its inverse breadcrumbs, then follows the durable home breadcrumb one checked cell at a time. The breadcrumb is a loop-erased list of actual successful moves from origin to the current absolute pose. Each successful movement updates both the pose and breadcrumb in the same checkpoint. It does not ask for confirmation or continue mining. At base it stores a service checkpoint so `miner resume` can unload/resupply and return to the exact saved work cursor. If power is lost during travel, each successful physical action remains checkpointed; a pending action remains uncertain and is refused.

The shell command cannot interrupt a currently running synchronous mining program. Stop that program first with the turtle terminal's standard interrupt (Ctrl+T), then run `miner home` at the prompt. The command still enforces known-pose, recorded-route, and per-move fuel safety requirements.

## Public entry points

- `miner home` dispatches in `src/branch_miner.lua`.
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

Requires the existing local state snapshot, CC:Tweaked filesystem and serialization APIs, a known pose, and a recorded return route. Coordinates are absolute relative to the fixed surface origin, not GPS world coordinates. It cannot interrupt a running program from a separate shell invocation. An uncleared block, inadequate fuel, inventory pressure, uncertain pose, or persistence failure stops the command at the last committed checkpoint. Software cannot guarantee a physical return across an unconfirmed movement or turn.

## Verification

`tests/recovery_status.lua` covers command dispatch without a confirmation prompt and verifies that a home command at base leaves a paused service checkpoint. `tests/home_breadcrumb.lua` covers per-move pose/trail updates, loop removal, blocked return, exact home replay, and invalid persisted breadcrumbs. `tests/persistence_state.lua` covers paused-state roundtrip and recovery admission. In-world return geometry and interrupted return recovery still require operator verification.
