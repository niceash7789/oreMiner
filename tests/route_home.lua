local RouteHome = require("src.navigation.route_home")
local KnownRoute = require("src.fuel.known_route")
local Pose = require("src.navigation.pose")
local Result = require("src.safety.result")

local home = { x = 0, y = 0, z = 0, facing = 0 }
local route = assert(KnownRoute.new(home))
local committed = {
    { x = 0, y = 0, z = -1 },
    { x = 0, y = 0, z = -2 },
}
for index, position in ipairs(committed) do
    local previous = index == 1 and home or committed[index - 1]
    assert(KnownRoute.recordMove(route, previous, position))
end

local pose = { x = 0, y = 0, z = -2, facing = 1 }
local movementCount, turnCount = 0, 0
local returned, outcome = RouteHome.run({
    pose = pose,
    route = route,
    homeFacing = 0,
    move = function(direction)
        local nextPose, result = Pose.afterMove(pose, direction, true)
        assert(result.ok)
        pose = nextPose
        movementCount = movementCount + 1
        return pose, Result.new(true, "MOVE_COMMITTED")
    end,
    turn = function(direction)
        local nextPose, result = Pose.afterTurn(pose, direction, true)
        assert(result.ok)
        pose = nextPose
        turnCount = turnCount + 1
        return pose, Result.new(true, "TURN_COMMITTED")
    end,
})
assert(outcome.ok and outcome.code == "HOME_REACHED")
assert(returned.x == 0 and returned.y == 0 and returned.z == 0 and returned.facing == 0)
assert(movementCount == 2 and turnCount > 0)

local unknownMoves = 0
local unknownPose = { x = 8, y = 0, z = 0, facing = 0 }
local stopped, unknownOutcome = RouteHome.run({
    pose = unknownPose,
    route = route,
    move = function() unknownMoves = unknownMoves + 1 return unknownPose, Result.new(true, "MOVE") end,
    turn = function() return unknownPose, Result.new(true, "TURN") end,
})
assert(unknownOutcome.code == "UNKNOWN_CURRENT_ROUTE")
assert(stopped.x == unknownPose.x and unknownMoves == 0)

local failedPose = { x = 0, y = 0, z = -2, facing = 0 }
local failedMoves = 0
local failedResult, failedOutcome = RouteHome.run({
    pose = failedPose,
    route = route,
    move = function()
        failedMoves = failedMoves + 1
        return failedPose, Result.new(false, "RETURN_BLOCKED")
    end,
    turn = function(direction)
        local nextPose = assert(Pose.afterTurn(failedPose, direction, true))
        failedPose = nextPose
        return failedPose, Result.new(true, "TURN_COMMITTED")
    end,
})
assert(failedOutcome.code == "RETURN_BLOCKED" and failedMoves == 1)
assert(failedResult.z == -2)

print("route home checks passed")
