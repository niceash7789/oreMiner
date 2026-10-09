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
- `require("src.navigation.stair_route")` exposes `StairRoute.descend(options)` and `StairRoute.returnToSurface(options)` for checked route composition.
- `require("src.navigation.floor_landing").prepare({ pose, clear, move, turn })` clears the flat landing and returns at its canonical centre.

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

`src/navigation/stair_route.lua` composes the fixed surface entry and a configured number of checked stair slices. It reports per-slice progress to an optional persistence callback, requires a landing-preparation callback to finish at the centre one block beyond the final rear cell, and saves the origin/mouth/rear/landing poses through a required callback. `src/navigation/floor_landing.lua` clears the three rows and three-wide columns with three-block headroom, then returns to the centre row. The route's return path backs from the landing to the saved rear cell, climbs each slice without digging, reverses the first-floor surface entry or prior-floor landing crossing, and checks every expected pose.

`Checkpoint.recordFloorLanding` and the state codec durably record validated landing routes, enforce fixed facing-relative geometry and contiguous floor origins, and expose defensive getters. `MiningCursor.stairs(floor, step, action)` now supplies validated next-action cursors for surface entry, stair slices, and landing preparation, but the active coordinator does not yet emit them or invoke the surface/stair route. It still uses the origin-level baseline. Torch niches, floor lifecycle, service/resume across floors, and in-world verification remain outstanding.

## Checklist status

S01 and the landing carve/checkpoint building blocks are covered by `tests/navigation_stair_slice.lua`, `tests/floor_landing.lua`, `tests/stair_route.lua`, and landing persistence cases in `tests/persistence_state.lua`. S02 remains unchecked until the active coordinator invokes these routes with durable intent and cursor boundaries.
