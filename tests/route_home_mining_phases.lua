-- Run from the project root with: lua tests/route_home_mining_phases.lua
local FloorGrid = require("src.navigation.floor_grid")
local BranchTraversal = require("src.navigation.branch_traversal")
local KnownRoute = require("src.fuel.known_route")
local RouteHome = require("src.navigation.route_home")
local Pose = require("src.navigation.pose")
local Result = require("src.safety.result")

local function samePosition(left, right)
    return left.x == right.x and left.y == right.y and left.z == right.z
end

local function exerciseReturn(startPose, route, shouldFailAt)
    local pose = { x = startPose.x, y = startPose.y, z = startPose.z, facing = startPose.facing }
    local moves, turns = 0, 0
    local returned, outcome = RouteHome.run({
        pose = pose,
        route = route,
        homeFacing = 0,
        move = function(direction)
            moves = moves + 1
            if moves == shouldFailAt then
                return pose, Result.new(false, "RETURN_BLOCKED")
            end
            local nextPose, status = Pose.afterMove(pose, direction, true)
            assert(status.ok)
            assert(KnownRoute.hasEdge(route, pose, nextPose), "home return must use a recorded edge")
            pose = nextPose
            return pose, Result.new(true, "MOVE_COMMITTED")
        end,
        turn = function(direction)
            turns = turns + 1
            local nextPose, status = Pose.afterTurn(pose, direction, true)
            assert(status.ok)
            pose = nextPose
            return pose, Result.new(true, "TURN_COMMITTED")
        end,
    })
    if shouldFailAt then
        assert(outcome.code == "RETURN_BLOCKED" and moves == shouldFailAt,
            "a failed inverse edge stops return immediately")
        assert(samePosition(returned, pose), "failed move must leave committed pose unchanged")
    else
        assert(outcome.ok and outcome.code == "HOME_REACHED")
        assert(returned.x == 0 and returned.y == 0 and returned.z == 0 and returned.facing == 0,
            "return reaches exact surface origin and facing")
        assert(moves > 0 and turns > 0)
    end
end

local function routeTo(checkpoint)
    local route = assert(KnownRoute.new({ x = 0, y = 0, z = 0, facing = 0 }))
    local point = { x = 0, y = 0, z = 0, facing = 0 }
    for _, axis in ipairs({ "x", "y", "z" }) do
        while point[axis] ~= checkpoint[axis] do
            local nextPose = { x = point.x, y = point.y, z = point.z, facing = point.facing }
            nextPose[axis] = nextPose[axis] + (checkpoint[axis] > point[axis] and 1 or -1)
            assert(KnownRoute.recordMove(route, point, nextPose))
            point.x, point.y, point.z = nextPose.x, nextPose.y, nextPose.z
        end
    end
    return route
end

local origin = { x = 0, y = 0, z = 0, facing = 0 }
local route = assert(KnownRoute.new(origin))

-- Main-shaft lower cell, reached from the floor-1 recorded landing via main entry.
local landing = { x = 0, y = -8, z = -13, facing = 0 }
local mainFacing = 1
local mainStart = { x = landing.x, y = landing.y, z = landing.z, facing = mainFacing }
local cursor = { x = origin.x, y = origin.y, z = origin.z, facing = origin.facing }
local function recordStep(target)
    assert(KnownRoute.recordMove(route, cursor, target))
    cursor = { x = target.x, y = target.y, z = target.z, facing = cursor.facing }
end
for _ = 1, 4 do
    local target = assert(Pose.afterMove(cursor, "forward", true))
    recordStep(target)
end
for _ = 1, 8 do
    local target = assert(Pose.afterMove(cursor, "forward", true))
    recordStep(target)
    target = assert(Pose.afterMove(cursor, "down", true))
    recordStep(target)
end
recordStep(landing)
local rightTurn = assert(Pose.afterTurn(cursor, "right", true))
cursor = rightTurn
for _ = 1, 5 do
    local target = assert(Pose.afterMove(cursor, "forward", true))
    recordStep(target)
end
assert(cursor.y == -8 and cursor.facing == mainFacing)
exerciseReturn(cursor, route)
exerciseReturn(cursor, route, 1)

-- Branch lower offset and upper scan offset, based on the same recorded floor.
local grid = assert(FloorGrid.new(origin, 0, { floor = 1, pose = landing }, 8))
local junction = assert(grid.junction(4))
for _, side in ipairs({ "left", "right" }) do
    local branch = assert(grid.branch(junction, side))
    local traversal = assert(BranchTraversal.new(branch, 4))
    local lowerOffset = assert(traversal.outboundPose(3))
    assert(lowerOffset.y == -8 and lowerOffset.facing == branch.facing)
    exerciseReturn(lowerOffset, routeTo(lowerOffset))

    local upperOffset = assert(traversal.upperReturnPose(3))
    assert(upperOffset.y == -7 and upperOffset.facing == (branch.facing + 2) % 4)
    exerciseReturn(upperOffset, routeTo(upperOffset))
end

print("route home mining-phase checks passed")
