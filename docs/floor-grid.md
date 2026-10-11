# Floor branch grid

## Purpose

Define floor geometry from a recorded staircase landing while retaining the fixed surface origin and initial facing.

## Implemented behavior

`FloorGrid.new(origin, staircaseFacing, landing)` requires the original surface pose and an explicit `{ floor, pose }` landing record. It verifies V1 geometry including the forward move from stair rear-centre to landing-centre: floor 1 is 13 blocks forward from origin; each later segment adds one landing crossing, eight stair slices, and one landing-centre move (10 blocks per floor interval). The floor main tunnel faces right from the recorded staircase direction. The first shaft-pair junction is reached after one full configured spacing segment from the landing (three blocks by default); later junctions are another spacing segment apart. The coordinator advances continuously through each segment, scanning each cell, before turning into the paired shafts. `grid.junction(mainOffset)` locates a lower-level junction from the landing, and `grid.branch(junctionPose, side)` gives the left or right branch's lower-lane origin, heading, and canonical main-facing junction. The same paired geometry is anchored independently at each floor's landing.

`MainShaft.new(landingPose, mainFacing, length)` defines the straight main-shaft segment from that recorded landing. It accepts only the canonical right-turn heading and returns bounded poses along the segment; `isCanonicalReturn` recognizes the exact landing centre with main-shaft facing. The active coordinator turns right after landing, excavates each configured cell two blocks high, and returns over its recorded route to the landing before it marks the floor complete. The 10-block mock geometry test verifies endpoint displacement for every stairs-facing direction.

## Public entry points

- `require("src.navigation.floor_grid")`
- `require("src.navigation.main_shaft")`
- `FloorGrid.new(origin, staircaseFacing, landing)` returns a floor grid and structured status.
- `grid.junction(mainOffset)` returns a main-tunnel junction pose.
- `grid.branch(junctionPose, "left"|"right")` returns branch origin, facing, and `junctionFacing`.
- `MainShaft.new(landingPose, mainFacing, length)` returns a bounded main-shaft geometry object and structured status.
- `shaft.pose(offset)` returns the expected pose for an offset from zero through the configured length.
- `shaft.isCanonicalReturn(pose)` checks exact landing coordinates and main-shaft orientation.

## Invariants and assumptions

- Pose coordinates use `0=north/-z`, `1=east/+x`, `2=south/+z`, `3=west/-x`.
- The supplied landing is the canonical floor entry and faces the initial staircase direction.
- Floor one geometry is four surface-entry moves, eight slices, and one move to the landing centre. Each later interval is one prior-landing crossing, eight slices, and one move to its landing centre; unsupported geometry is rejected.
- Branch headings are perpendicular to the floor main heading, and both begin at the same lower-lane junction.
- Returned poses are newly allocated; inputs are not mutated.

## Dependencies and limitations

Both geometry modules are pure and do not move the turtle. The main-shaft helper does not clear blocks, persist a cursor, or execute a return; the coordinator retains those responsibilities.

## Verification

Run `lua tests/navigation_floor_grid.lua` and `lua tests/navigation_main_shaft.lua` from the repository root. Tests cover first and later landings, paired headings, all main-shaft facings, the 10-block endpoint and exact landing pose, and invalid geometry. Both tests pass under Lua 5.4.
