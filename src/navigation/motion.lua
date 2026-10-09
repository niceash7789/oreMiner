-- Raw turtle motion and pose/route commit boundary.
-- Policy, pending-action persistence, and retry decisions belong to callers.
local Pose = require("src.navigation.pose")
local KnownRoute = require("src.fuel.known_route")
local RoutePolicy = require("src.fuel.route_policy")
local Result = require("src.safety.result")
local FuelLevel = require("src.fuel.level")

local Motion = {}

local movementApi = {
    forward = "forward",
    back = "back",
    up = "up",
    down = "down",
}

local function failure(code, message)
    return Result.new(false, code, message)
end

local function fuelFailure(level, requiredFuel)
    if type(level) ~= "number" then
        return failure("NO_FUEL", "Fuel level is unavailable; stop before movement.")
    end
    if type(level) == "number" and type(requiredFuel) == "number"
        and level >= requiredFuel then
        return failure("FUEL_POLICY_FAILED", "Fuel refuelling did not establish a safe tank level.")
    end
    if type(level) == "number" and type(requiredFuel) == "number"
        and level >= 0 then
        return failure("NO_FUEL", "Fuel reserve cannot be maintained; stop before movement.")
    end
    return failure("NO_FUEL", "Fuel level is unavailable; stop before movement.")
end

function Motion.move(pose, route, movement, turtleApi)
    local apiName = movementApi[movement]
    if not apiName then return nil, failure("INVALID_MOVEMENT", "Unknown movement direction.") end
    local nextPose, poseStatus = Pose.afterMove(pose, movement, true)
    if not poseStatus.ok then return nil, poseStatus end

    local fuelBefore
    if type(turtleApi.getFuelLevel) == "function" then
        fuelBefore = turtleApi.getFuelLevel()
    end
    local apiResult = turtleApi[apiName]()
    if apiResult ~= true then return Pose.afterMove(pose, movement, apiResult) end
    local fuelAfter
    if type(turtleApi.getFuelLevel) == "function" then
        fuelAfter = turtleApi.getFuelLevel()
    end

    local updated, result = Pose.afterMove(pose, movement, true)
    if not result.ok then return nil, result end
    if route then
        local recorded, reason = KnownRoute.recordMove(route, pose, updated)
        if not recorded then return nil, failure("ROUTE_RECORD_FAILED", tostring(reason)) end
    end
    return updated, Result.new(true, "MOVE_COMMITTED", nil, {
        fuelUsed = FuelLevel.consumed(fuelBefore, fuelAfter),
    })
end

function Motion.moveWithPolicy(pose, route, movement, turtleApi, policy)
    local allowed, reason, requiredFuel = RoutePolicy.canMove({
        pose = pose,
        route = route,
        movement = movement,
        reserve = policy.reserve,
        getFuelLevel = policy.getFuelLevel,
        refuel = policy.refuel,
    })
    if not allowed then
        if reason == "INSUFFICIENT_FUEL" then
            return pose, fuelFailure(policy.getFuelLevel(), requiredFuel)
        end
        if reason == "INVALID_FUEL_LEVEL" then
            return pose, fuelFailure(policy.getFuelLevel(), nil)
        end
        return pose, failure(reason or "INSUFFICIENT_FUEL", "Movement denied by route fuel policy.")
    end
    local ready, intentReason = policy.beforeMove()
    if not ready then
        return pose, failure(intentReason or "PERSISTENCE_FAILED", "Movement intent was not saved.")
    end
    return Motion.move(pose, route, movement, turtleApi)
end

function Motion.turn(pose, direction, turtleApi)
    if direction ~= "left" and direction ~= "right" then
        return nil, failure("INVALID_TURN", "Turn direction must be left or right.")
    end
    local action = direction == "left" and turtleApi.turnLeft or turtleApi.turnRight
    return Pose.afterTurn(pose, direction, action())
end

return Motion
