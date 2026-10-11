# Floor branch grid

## Purpose

Define floor geometry from a recorded staircase landing while retaining the fixed surface origin and initial facing.

## Implemented behavior

`FloorGrid.new(origin, staircaseFacing, landing, stairStepsPerFloor)` requires the original surface pose, an explicit `{ floor, pose }` landing record, and the validated stair interval. It verifies V1 geometry including the forward move from stair rear-centre to landing-centre: with four steps, floor 1 is 9 blocks forward from origin; each later segment adds one landing crossing, four stair slices, and one landing-centre move (6 blocks per floor interval). In general, the forward offset is `3 + floor * (stairStepsPerFloor + 2)` and the depth is `-floor * stairStepsPerFloor`. The coordinator mines a complete right-facing main-shaft grid, returns to the landing, then mines its left-facing mirror. Each side advances continuously through a configured spacing segment before its paired shafts. `grid.junction(mainOffset, mainSide)` locates either side's lower-level junction, and `grid.branch(junctionPose, side)` turns relative to that junction's heading.

`MainShaft.new(landingPose, mainFacing, length)` defines either straight main-shaft segment from that recorded landing. It accepts the perpendicular right or left heading and returns bounded poses; `isCanonicalReturn` recognizes the exact landing centre with that main heading. The coordinator excavates each configured cell two blocks high and returns over recorded cells. It marks the floor complete only after both passes. The 10-block geometry test verifies each direction from every stairs-facing orientation.

## Public entry points

- `require("src.navigation.floor_grid")`
- `require("src.navigation.main_shaft")`
- `FloorGrid.new(origin, staircaseFacing, landing, stairStepsPerFloor)` returns a floor grid and structured status.
- `grid.mainFacingFor("right"|"left")` returns a main heading.
- `grid.junction(mainOffset, "right"|"left")` returns a main-shaft junction pose; an omitted side retains the legacy right default.
- `grid.branch(junctionPose, "left"|"right")` returns branch origin, facing, and `junctionFacing`.
- `MainShaft.new(landingPose, mainFacing, length)` returns a bounded main-shaft geometry object and structured status.
- `shaft.pose(offset)` returns the expected pose for an offset from zero through the configured length.
- `shaft.isCanonicalReturn(pose)` checks exact landing coordinates and main-shaft orientation.

## Invariants and assumptions

- Pose coordinates use `0=north/-z`, `1=east/+x`, `2=south/+z`, `3=west/-x`.
- The supplied landing is the canonical floor entry and faces the initial staircase direction.
- Floor one geometry is four surface-entry moves, the configured slices, and one move to the landing centre. Each later interval is one prior-landing crossing, the configured slices, and one move to its landing centre; unsupported geometry is rejected.
- Branch headings are perpendicular to their own main heading, and each pair begins at the same lower-lane junction. The two main sides have independent junction and torch identities.
- Returned poses are newly allocated; inputs are not mutated.

## Dependencies and limitations

Both geometry modules are pure and do not move the turtle. The floor grid uses `src/core/stair_geometry.lua` for the validated 4–64 slice interval; recovery passes the saved interval and fails closed if it is absent or invalid. The main-shaft helper does not clear blocks, persist a cursor, or execute a return; the coordinator retains those responsibilities. In-world geometry on both sides remains an operator check.

## Verification

Run `lua tests/navigation_floor_grid.lua` and `lua tests/navigation_main_shaft.lua` from the repository root. Tests cover first and later landings, paired headings, all main-shaft facings, the 10-block endpoint and exact landing pose, and invalid geometry. Both tests pass under Lua 5.4.
