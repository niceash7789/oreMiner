-- Run from the project root with: lua tests/navigation_floor_grid.lua
local FloorGrid = require("src.navigation.floor_grid")

local origin = { x = 0, y = 0, z = 0, facing = 0 }
local grid, status = FloorGrid.new(origin, 0, {
    floor = 1,
    pose = { x = 0, y = -8, z = -13, facing = 0 },
}, 8)
assert(status.ok, "recorded floor-one landing should create a grid")
assert(grid.mainFacing == 1, "main tunnel should turn right from staircase facing")

local junction = assert(grid.junction(3))
assert(junction.x == 3 and junction.y == -8 and junction.z == -13 and junction.facing == 1,
    "junction should be offset from the recorded landing along the floor main")

local left = assert(grid.branch(junction, "left"))
local right = assert(grid.branch(junction, "right"))
assert(left.origin.x == junction.x and left.origin.y == junction.y and left.origin.z == junction.z)
assert(left.facing == 0, "left branch should face north")
assert(right.facing == 2, "right branch should face south")

local opposite = assert(grid.junction(3, "left"))
assert(opposite.x == -3 and opposite.y == -8 and opposite.z == -13
    and opposite.facing == 3, "the opposite main shaft should leave the same landing")
local oppositeLeft = assert(grid.branch(opposite, "left"))
local oppositeRight = assert(grid.branch(opposite, "right"))
assert(oppositeLeft.facing == 2 and oppositeRight.facing == 0
    and oppositeLeft.junctionFacing == 3 and oppositeRight.junctionFacing == 3,
    "paired shafts must turn relative to the opposite main heading")
local invalidSide, invalidSideStatus = grid.junction(3, "back")
assert(invalidSide == nil and invalidSideStatus.code == "INVALID_MAIN_SIDE")

local secondGrid = assert(FloorGrid.new(origin, 0, {
    floor = 2,
    pose = { x = 0, y = -16, z = -23, facing = 0 },
}, 8))
assert(secondGrid.landing.pose.y == -16 and secondGrid.landing.pose.z == -23,
    "each floor grid should anchor to its own recorded landing")

local shortGrid = assert(FloorGrid.new(origin, 0, {
    floor = 2,
    pose = { x = 0, y = -8, z = -15, facing = 0 },
}, 4))
assert(shortGrid.landing.pose.y == -8 and shortGrid.landing.pose.z == -15,
    "four-step floors should derive their own landing geometry")
local offsetGrid = assert(FloorGrid.new(origin, 0, {
    floor = 2,
    pose = { x = 0, y = -11, z = -18, facing = 0 },
}, 4, 3))
assert(offsetGrid.landing.pose.y == -11 and offsetGrid.landing.pose.z == -18,
    "first-floor depth offset must carry through later landing geometry")
local noOffsetGrid, noOffsetStatus = FloorGrid.new(origin, 0, {
    floor = 2,
    pose = { x = 0, y = -8, z = -15, facing = 0 },
}, 4, 3)
assert(noOffsetGrid == nil and noOffsetStatus.code == "LANDING_MISMATCH")

local missingLanding, missingStatus = FloorGrid.new(origin, 0, { floor = 1 }, 8)
assert(missingLanding == nil and missingStatus.code == "INVALID_LANDING",
    "grid creation must require a recorded landing pose")
local wrongLanding, wrongStatus = FloorGrid.new(origin, 0, {
    floor = 1,
    pose = { x = 0, y = -8, z = -8, facing = 0 },
}, 8)
assert(wrongLanding == nil and wrongStatus.code == "LANDING_MISMATCH",
    "grid must reject a landing inconsistent with the fixed origin contract")
local wrongFacing, facingStatus = FloorGrid.new(origin, 1, {
    floor = 1,
    pose = { x = 0, y = -8, z = -13, facing = 0 },
}, 8)
assert(wrongFacing == nil and facingStatus.code == "ORIGIN_FACING_MISMATCH",
    "grid must preserve the initial facing contract")

local missingSteps, missingStepsStatus = FloorGrid.new(origin, 0, {
    floor = 1, pose = { x = 0, y = -4, z = -9, facing = 0 },
})
assert(missingSteps == nil and missingStepsStatus.code == "INVALID_STAIR_STEPS",
    "grid must require a validated interval instead of assuming eight")

print("navigation floor-grid checks passed")
