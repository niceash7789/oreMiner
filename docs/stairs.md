# Stairs slice navigation

## Purpose

Carve one bounded 3-wide by 4-tall descending stairs slice, restore the turtle to the route centreline, and provide the exact inverse climb.

## Implemented behavior

`StairSlice.descend` starts at a centre-bottom stairs checkpoint. It clears and enters the next slice at its centre height, clears one block below and two above in the centre, left, and right columns, unwinds each lateral and vertical excursion, restores the original stairs facing, and moves down to the next centre-bottom checkpoint. A successful slice advances exactly one block forward and one block down. After the cross-section is cleared and before the final down move, the optional torch callback targets an already-cleared right-column cell inside the passage; it does not dig a side niche or add a route move. If clearing, torch placement, or the final descent fails after a safe lateral unwind, the module follows the recorded clear approach back to the last centre-bottom checkpoint before returning the typed failure; an inverse failure is propagated and stops the route.

`StairSlice.climb` follows the inverse slice geometry: up, forward to cancel the lateral offset, then back to the preceding centreline. It does not call a clear or dig operation. `StairRoute.returnToSurface` validates that resulting offset before continuing the recorded route.

The job configuration accepts `mining.stairStepsPerFloor` from 4 through 64 and an optional `mining.firstFloorDepthOffset` from 0 through 60, with their sum at most 64. Floor 1 is `stairStepsPerFloor + firstFloorDepthOffset` blocks below the surface; every later floor is `stairStepsPerFloor` blocks below the prior landing. Both values are saved with the run and used for stair cursors, landing geometry, and recovery validation. Changing either value during a saved run is rejected. The tracked example uses four steps and zero offset.

`StairRoute.returnToSurface` preflights the saved origin, entry length, step count, and mouth/rear/landing geometry against the V1 route before issuing its first inverse action. A pose-valid but geometrically corrupted route returns `LANDING_ROUTE_INVALID` without moving.

The deterministic slice test runs the geometry for all four initial facings at a translated pose, verifies all twelve route-relative target cells, checks the centre and lateral clear sub-phases at their expected positions and headings (proving each lateral sweep returns to centre before the next begins), and asserts the exact forward/down displacement with facing preserved. `tests/stair_route.lua` composes recorded floor 2 and floor 1 inverse routes through the four-block entry to exact surface origin, injects a failed inverse move to prove the route stops immediately, and verifies corrupted route geometry is rejected before any movement. The integrated fake-turtle test now covers a two-slice first-floor offset and later normal intervals. The in-world stairs width, height, and offset remain operator checks.

`StairRoute.descend` accepts an optional `afterStep` callback after a successful slice and saved progress. The active coordinator persists the next unfinished stair cursor, then checks inventory pressure at the restored centre-bottom pose. A service round trip uses recorded route edges and restores the exact pose and cursor. Service failure stops descent before another slice. On reboot, `cross_landing` is admitted only from the exact preceding landing with complete origin, mouth, rear, and landing geometry plus a recorded route home; resume budgets the new recorded route, crosses once, and runs the normal descent. Each physical dig now has durable intent and commit, and a crash with a pending dig stops as `POSITION_UNCERTAIN`. Active stair moves and turns atomically save their inverse edge with pending intent, then commit the new pose and remove that edge together. A literal API failure cancels the provisional edge and intent while retaining the old pose; a failed commit leaves durable pending intent and the edge for a certainty stop. Mid-slice and `prepare_landing` cursors remain fail-closed with distinct `STAIR_SLICE_RESUME_UNSUPPORTED` and `LANDING_CARVE_RESUME_UNSUPPORTED` reasons; no automatic in-slice replay is admitted.

## Public entry points

- `require("src.navigation.stair_slice")`
- `StairSlice.descend({ pose, clear, move, turn })`
- `StairSlice.climb({ pose, move, turn })`
- `require("src.navigation.stair_route")` exposes `descend`, `returnToSurface`, and `resumeToLanding`.
- `StairRoute.descend` accepts `afterStep`, which receives `{ floor, stairStep, pose, nextStep, nextAction }` after successful slice progress persistence.
- `require("src.core.stair_geometry").stepsForFloor(interval, offset, floor)` returns the bounded slice count for one descent.
- `require("src.navigation.floor_landing").prepare({ pose, clear, move, turn })`

## Invariants and assumptions

- Pose and facing are accepted only through successful checked callbacks.
- Every lateral move and turn is recorded and unwound in strict reverse order.
- Each lateral column returns to the target centreline before another column or the final descent begins.
- Successful descent preserves the starting facing and has net displacement one forward plus one down.
- The first landing includes the configured offset; later landings are exactly the configured interval below the previous landing. Saved routes retain their actual slice counts.
- Stair torches occupy an already-cleared right-column passage cell; no torch-specific dig or lateral move is permitted.
- The service callback runs only at a committed centre-bottom checkpoint; it cannot interrupt a lateral sweep.
- Inverse climb stays on the recorded centreline. Its checked movement callback may dig a block in the target cell and retry within limits.
- Callers remain responsible for fuel admission, durable movement intent/commit, and bounded block/entity recovery.

## Dependencies and limitations

The module uses `src/navigation/pose.lua`, `src/navigation/action_stack.lua`, shared result/contract modules, and checked movement callbacks. `src/branch_miner.lua` persists stair move/turn intent and route edges through `src/persistence/checkpoint.lua`; `Session.beginRouteAction`, `commitRouteAction`, and `cancelRouteAction` are the storage entry points. The deterministic route and persistence tests cover geometry, intent uncertainty, atomic commit, and literal-failure cancellation. `tests/navigation_stair_slice.lua` verifies all four facing-relative target grids and injects a literal failure at every move/turn call in a successful slice trace, checking that reported pose matches simulated world pose. `tests/persistence_recovery.lua` injects committed snapshots with pending move/turn/dig intents and provisional stair route edges; recovery must keep them uncertain. The active coordinator's recovery classifier still rejects in-slice and landing-carve cursors before any movement. Hardware geometry, service round trips, and restart behavior remain unverified in-world.

## Falling-block observation races

Stair clearing uses `DigClear.run` through the coordinator's forward, up, and down dig callbacks. A block that vanishes between detection and inspection is observed again without digging. If a dig reports failure after the target vanishes, clearing likewise rechecks the cell. Persistent blocks still stop as `UNBREAKABLE_BLOCK`; dig attempts, elapsed time, and repeated observation races are bounded. This applies to all callers of the shared dig helper. The public entry point is `src/safety/dig_clear.lua` (`DigClear.run`), with `inspect` returning `false` only for a vanished target. It depends on checked CC:Tweaked detect, inspect, and dig callbacks. In-world falling gravel behavior remains to be verified.
