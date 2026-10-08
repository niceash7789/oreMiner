# Floor branch grid

## Purpose

Define the paired branch grid's coordinate frame from a recorded staircase landing while retaining the fixed surface origin and initial facing.

## Implemented behavior

`FloorGrid.new(origin, staircaseFacing, landing)` requires the original surface pose and an explicit `{ floor, pose }` landing record. It verifies the V1 geometry: four level entry blocks, eight forward/down stair slices per floor, and the recorded staircase facing. The floor main tunnel faces right from that direction. `grid.junction(mainOffset)` locates a lower-level junction from the landing, and `grid.branch(junctionPose, side)` gives the left or right branch's lower-lane origin, heading, and canonical junction facing. The same paired geometry is anchored independently at each floor's landing.

## Public entry points

- `require("src.navigation.floor_grid")`
- `FloorGrid.new(origin, staircaseFacing, landing)` returns a floor grid and structured status.
- `grid.junction(mainOffset)` returns a main-tunnel junction pose.
- `grid.branch(junctionPose, "left"|"right")` returns branch origin, facing, and `junctionFacing`.

## Invariants and assumptions

- Pose coordinates use `0=north/-z`, `1=east/+x`, `2=south/+z`, `3=west/-x`.
- The supplied landing is the canonical floor entry and faces the initial staircase direction.
- Each V1 floor interval is eight slices and the surface entry is four blocks; unsupported landing geometry is rejected.
- Branch headings are perpendicular to the floor main heading, and both begin at the same lower-lane junction.
- Returned poses are newly allocated; inputs are not mutated.

## Dependencies and limitations

This is pure geometry and depends on no other runtime module. It is deliberately not wired into `src/branch_miner.lua` until the staircase phase creates and persists a real landing record. It does not create or persist landing records, move the turtle, carve tunnels, or implement return routing; those remain separate navigation work. The future integration point is the floor-phase setup immediately after a landing is recorded.

## Verification

Run `lua tests/navigation_floor_grid.lua` from the repository root. The test covers first and later landings, paired headings, and invalid/missing landing contracts.
