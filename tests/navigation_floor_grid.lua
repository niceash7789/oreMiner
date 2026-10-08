-- Run from the project root with: lua tests/navigation_floor_grid.lua
local FloorGrid = require("src.navigation.floor_grid")

local origin = { x = 0, y = 0, z = 0, facing = 0 }
local grid, status = FloorGrid.new(origin, 0, {
    floor = 1,
    pose = { x = 0, y = -8, z = -12, facing = 0 },
})
assert(status.ok, "recorded floor-one landing should create a grid")
assert(grid.mainFacing == 1, "main tunnel should turn right from staircase facing")

local junction = assert(grid.junction(3))
assert(junction.x == 3 and junction.y == -8 and junction.z == -12 and junction.facing == 1,
    "junction should be offset from the recorded landing along the floor main")

local left = assert(grid.branch(junction, "left"))
local right = assert(grid.branch(junction, "right"))
assert(left.origin.x == junction.x and left.origin.y == junction.y and left.origin.z == junction.z)
assert(left.facing == 0, "left branch should face north")
assert(right.facing == 2, "right branch should face south")

local secondGrid = assert(FloorGrid.new(origin, 0, {
    floor = 2,
    pose = { x = 0, y = -16, z = -20, facing = 0 },
}))
assert(secondGrid.landing.pose.y == -16 and secondGrid.landing.pose.z == -20,
    "each floor grid should anchor to its own recorded landing")

local missingLanding, missingStatus = FloorGrid.new(origin, 0, { floor = 1 })
assert(missingLanding == nil and missingStatus.code == "INVALID_LANDING",
    "grid creation must require a recorded landing pose")
local wrongLanding, wrongStatus = FloorGrid.new(origin, 0, {
    floor = 1,
    pose = { x = 0, y = -8, z = -8, facing = 0 },
})
assert(wrongLanding == nil and wrongStatus.code == "LANDING_MISMATCH",
    "grid must reject a landing inconsistent with the fixed origin contract")
local wrongFacing, facingStatus = FloorGrid.new(origin, 1, {
    floor = 1,
    pose = { x = 0, y = -8, z = -12, facing = 0 },
})
assert(wrongFacing == nil and facingStatus.code == "ORIGIN_FACING_MISMATCH",
    "grid must preserve the initial facing contract")

print("navigation floor-grid checks passed")
