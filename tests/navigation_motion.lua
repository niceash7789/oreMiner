local Motion = require("src.navigation.motion")
local Pose = require("src.navigation.pose")
local KnownRoute = require("src.fuel.known_route")
local RoutePolicy = require("src.fuel.route_policy")
local FakeTurtle = require("tests.fake_turtle")

local function assertPose(actual, expected, message)
    assert(actual and actual.x == expected.x and actual.y == expected.y
        and actual.z == expected.z and actual.facing == expected.facing, message)
end

local start = assert(Pose.new(0, 0, 0, 0))
local route = assert(KnownRoute.new(start))
local world = FakeTurtle.new(start)
local api = {
    forward = function() return world:move("forward", true) end,
    back = function() return world:move("back", true) end,
    up = function() return world:move("up", true) end,
    down = function() return world:move("down", true) end,
    turnLeft = function() return world:turn("left", true) end,
    turnRight = function() return world:turn("right", true) end,
}

local moved, result = Motion.move(start, route, "forward", api)
assert(result.ok and moved.z == -1, "successful movement commits pose")
assert(require("src.core.contracts").isResult(result), "movement returns a shared typed result")
assert(KnownRoute.hasEdge(route, start, moved), "successful movement records route edge")
assertPose(start, { x = 0, y = 0, z = 0, facing = 0 }, "input pose remains immutable")

local failedApi = { forward = function() return "unexpected" end }
local unchanged, failed = Motion.move(start, route, "forward", failedApi)
assert(failed.code == "MOVE_FAILED", "non-true movement result fails")
assert(require("src.core.contracts").isResult(failed), "failed movement returns a shared typed result")
assertPose(unchanged, start, "failed movement preserves pose")
assert(not KnownRoute.hasEdge(route, start, unchanged), "failed movement adds no route edge")

local turned, turnResult = Motion.turn(moved, "right", api)
assert(turnResult.ok and turned.facing == 1, "successful turn commits facing")
local unturned, turnFailure = Motion.turn(moved, "left", {
    turnLeft = function() return 1 end,
})
assert(turnFailure.code == "TURN_FAILED", "non-true turn result fails")
assertPose(unturned, moved, "failed turn preserves pose")

local deniedMoves = 0
local deniedPose, denied = Motion.moveWithPolicy(moved, route, "forward", {
    forward = function() deniedMoves = deniedMoves + 1 return true end,
}, {
    reserve = 10,
    getFuelLevel = function() return 1 end,
    refuel = function() return false end,
    beforeMove = function() error("denied move must not persist intent") end,
})
assert(denied.code == "NO_FUEL",
    "failed refuelling should stop safely before the proposed movement")
assertPose(deniedPose, moved, "denied movement preserves pose")
assert(deniedMoves == 0, "denied movement must not call turtle API")

local unknownFuelMoves = 0
local unknownFuelPose, unknownFuel = Motion.moveWithPolicy(moved, route, "forward", {
    forward = function() unknownFuelMoves = unknownFuelMoves + 1 return true end,
}, {
    reserve = 10,
    getFuelLevel = function() return "unavailable" end,
    beforeMove = function() error("invalid fuel must not persist movement intent") end,
})
assert(unknownFuel.code == "NO_FUEL",
    "an unavailable fuel reading should fail closed with fatal NO_FUEL")
assertPose(unknownFuelPose, moved, "invalid fuel preserves pose")
assert(unknownFuelMoves == 0, "invalid fuel must not call turtle API")

local admittedMoves = 0
local fuelLevel = 20
local admittedPose, admitted = Motion.moveWithPolicy(moved, route, "forward", {
    forward = function() admittedMoves = admittedMoves + 1 return true end,
    getFuelLevel = function()
        local current = fuelLevel
        fuelLevel = fuelLevel - 1
        return current
    end,
}, {
    reserve = 1,
    getFuelLevel = function() return 20 end,
    beforeMove = function() return true end,
})
assert(admitted.ok and admittedMoves == 1, "admitted movement should call physical API")
assert(admittedPose.z == -2, "admitted movement should commit its pose")
assert(admitted.fuelUsed == 1, "successful movement reports the observed fuel delta")

local unlimitedPose, unlimitedResult = Motion.move(start, nil, "forward", {
    forward = function() return true end,
    getFuelLevel = function() return "unlimited" end,
})
assert(unlimitedPose and unlimitedResult.fuelUsed == 0,
    "unlimited fuel has no numeric consumption delta")

local projected, projectedReason = RoutePolicy.canMove({
    pose = admittedPose,
    route = route,
    movement = "forward",
    reserve = 1,
    getFuelLevel = function() return 20 end,
})
assert(projected and projectedReason == "FUEL_SAFE", "route policy should admit known safe route")

print("navigation motion checks passed")
