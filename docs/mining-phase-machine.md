# Mining phase machine

## Purpose

Define legal logical phase changes for the active single-turtle surface-level mining cursor. The cursor records the next unit of work, so transitions happen after a unit completes and before its successor is persisted.

## Implemented behavior

`src/mining/phase_machine.lua` accepts a validated cursor and a completion event, rejects events unavailable in that phase, and returns a new cursor without mutating the input. It covers main-shaft cells, junction setup, branch outbound, turnaround, upper return, lower return, and arrival back at the junction. Optional updates are limited to the side and bounded progress offsets. New phase boundaries reset the local offset; each returned cursor gets a fresh stable work-unit ID.

## Public API

- `require("src.mining.cursor").transition(progress, event, updates?)` is the public entry point.
- Events: `main_cell_complete`, `main_segment_complete`, `branch_started`, `branch_cell_complete`, `outbound_complete`, `upper_return_started`, `upper_cell_complete`, `upper_return_complete`, `lower_return_started`, `lower_cell_complete`, `lower_return_complete`, `junction_reached`, and `main_facing_restored`.
- Success returns a copied cursor. Invalid source cursors return `INVALID_MINING_CURSOR`; illegal events or invalid updates return `INVALID_PHASE_TRANSITION`.

## Invariants and assumptions

- The input cursor remains unchanged; callers persist the returned cursor before starting its named next action.
- The machine changes logical progress only. It does not move the turtle, inspect the world, persist state, or infer that a physical action succeeded.
- A branch entry from the junction must supply `updates.side` as `left` or `right`.
- The phase sequence describes the currently implemented surface-level baseline. It does not imply staircase, multi-floor, service, resume, or vein phases are implemented.

## Dependencies and limitations

Pure Lua. The cursor API passes its validator to the transition module to avoid a circular module dependency. The active coordinator still constructs some cursors directly at its existing checkpoints; this item provides and verifies the transition authority, while wiring new stair/floor phases and recovery execution remain later checklist work.

## Verification

Run `lua tests/mining_phase_machine.lua` for legal and illegal transitions, immutability, offset boundaries, and return paths.

## Checklist status

The M01 entries in both the planning summary and Milestone 2 are checked after the focused test and syntax check passed. Multi-floor stairs, landing, service, resume, and vein phases remain separate work; this state machine still describes the active surface-level baseline.

