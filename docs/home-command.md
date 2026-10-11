# Operator home command

## Purpose

Let an operator stop a saved mining job at a known checkpoint and send the turtle to surface origin.

## Implemented behavior

Run `miner home` from the turtle shell after the mining program has stopped and returned to the prompt. The command loads the saved run, immediately marks it paused, unwinds a saved ore-vein excursion through its inverse breadcrumbs, then returns over recorded routes and stair landings. It does not ask for confirmation or continue mining. At base it stores a service checkpoint so `miner resume` can unload/resupply and return to the exact saved work cursor. If power is lost during travel, each successful physical action remains checkpointed; a pending action remains uncertain and is refused.

The shell command cannot interrupt a currently running synchronous mining program. Stop that program first with the turtle terminal's standard interrupt (Ctrl+T), then run `miner home` at the prompt. The command still enforces known-pose, recorded-route, and per-move fuel safety requirements.

## Public entry points

- `miner home` dispatches in `src/branch_miner.lua`.
- `Session.markPaused(pose, route, configSnapshot)` persists a resumable paused run in `src/persistence/checkpoint.lua`.
- `Session.markMining(pose, route, configSnapshot)` returns a paused run to active status before resume travel begins.
- `Session.setService(service, pose, route, configSnapshot)` records return-to-base and parked-at-base recovery stages.
- `Recovery.classify(state, loadCode)` admits known paused snapshots through the existing route and cursor recovery rules.

## Invariants and assumptions

- The command never digs or creates a route edge. It uses `travelStairRoute` and checked movement over recorded clear geometry.
- Saved pose certainty must be `known` and there must be no pending physical action before departure.
- A saved vein is unwound before ordinary route travel begins.
- The paused service record preserves the exact mining cursor, allowing `miner resume` to return to that job after base service.
- Every movement still passes the existing route-home fuel policy and durable intent/commit sequence.

## Dependencies and limitations

Requires the existing local state snapshot, CC:Tweaked filesystem and serialization APIs, a known pose, and a recorded return route. It cannot interrupt a running program from a separate shell invocation. A blocked route, inadequate fuel, uncertain pose, or persistence failure stops the command at the last committed checkpoint.

## Verification

`tests/recovery_status.lua` covers command dispatch without a confirmation prompt and verifies that a home command at base leaves a paused service checkpoint. `tests/persistence_state.lua` covers paused-state roundtrip and recovery admission. In-world return geometry and interrupted return recovery still require operator verification.
