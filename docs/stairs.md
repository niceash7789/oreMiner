# Stairs slice navigation

## Purpose

Carve one bounded 3-wide by 3-tall descending stairs slice, restore the turtle to the route centreline, and provide the exact non-digging inverse climb.

## Implemented behavior

`StairSlice.descend` starts at a centre-bottom stairs checkpoint. It clears and enters the next slice at its middle height, clears the centre column above and below, sweeps the left and right columns, unwinds each lateral excursion, restores the original stairs facing, and moves down to the next centre-bottom checkpoint. A successful slice advances exactly one block forward and one block down. If clearing or the final descent fails after a safe lateral unwind, the module follows the recorded clear approach back to the last centre-bottom checkpoint before returning the typed failure.

`StairSlice.climb` performs the exact inverse centreline movement: up, then back. It does not call a clear or dig operation.

## Public entry points

- `require("src.navigation.stair_slice")`
- `StairSlice.descend({ pose, clear, move, turn })` returns the final known pose and a structured outcome.
- `StairSlice.climb({ pose, move, turn })` returns the previous centre-bottom checkpoint and a structured outcome.

The `clear(direction)` callback accepts `forward`, `up`, or `down` and must return a structured outcome. The `move(movement)` and `turn(direction)` callbacks must be checked navigation boundaries returning `pose, outcome`.

## Invariants and assumptions

- Pose and facing are accepted only through successful checked callbacks.
- Every lateral move and turn is recorded and unwound in strict reverse order.
- Each lateral column returns to the target centreline before another column or the final descent begins.
- Successful descent preserves the starting facing and has net displacement one forward plus one down.
- Inverse climb assumes the recorded centreline route is already clear and never digs.
- Callers remain responsible for fuel admission, durable movement intent/commit, and bounded block/entity recovery.

## Dependencies

The module uses `src/navigation/pose.lua` for expected geometry, `src/navigation/action_stack.lua` for local reversible excursions, and the shared result/contract modules. The focused deterministic test uses the existing fake turtle with a small solid-block world harness.

## Current limitations

Only one slice and its inverse are implemented. The separate four-block surface-entry primitive is available, but the active coordinator does not yet invoke either route. Repeated eight-slice descent, landings, torch niches, persistence of stair sub-phases, and hierarchical return remain separate backlog items. No in-world verification has been performed.
