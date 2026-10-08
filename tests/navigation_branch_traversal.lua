-- Run from the project root with: lua tests/navigation_branch_traversal.lua
local FloorGrid = require("src.navigation.floor_grid")
local BranchTraversal = require("src.navigation.branch_traversal")

local origin = { x = 0, y = 0, z = 0, facing = 0 }
local grid = assert(FloorGrid.new(origin, 0, {
    floor = 1,
    pose = { x = 0, y = -8, z = -12, facing = 0 },
}))
local junction = assert(grid.junction(3))
local branch = assert(grid.branch(junction, "left"))
local traversal = assert(BranchTraversal.new(branch, 4))

local outboundStart = assert(traversal.outboundPose(0))
local outboundEnd = assert(traversal.outboundPose(4))
assert(outboundStart.x == junction.x and outboundStart.y == -8 and outboundStart.z == junction.z)
assert(outboundEnd.z == junction.z - 4 and outboundEnd.y == -8 and outboundEnd.facing == branch.facing,
    "outbound poses should advance along the lower branch lane")

local upperAtEnd = assert(traversal.upperReturnPose(0))
local upperAtJunction = assert(traversal.upperReturnPose(4))
assert(upperAtEnd.z == outboundEnd.z and upperAtEnd.y == -7)
assert(upperAtJunction.x == junction.x and upperAtJunction.y == -7
    and upperAtJunction.z == junction.z and upperAtJunction.facing == (branch.facing + 2) % 4,
    "upper return should scan the branch in reverse and reach the upper junction")

local canonical = assert(traversal.canonicalJunctionPose())
assert(canonical.x == junction.x and canonical.y == junction.y
    and canonical.z == junction.z and canonical.facing == junction.facing,
    "completed traversal should identify the canonical lower junction")

local invalid, invalidStatus = BranchTraversal.new(branch, 0)
assert(invalid == nil and invalidStatus.code == "INVALID_LENGTH")
local outOfRange, rangeStatus = traversal.upperReturnPose(5)
assert(outOfRange == nil and rangeStatus.code == "INVALID_RETURN_DISTANCE")

print("navigation branch-traversal checks passed")
