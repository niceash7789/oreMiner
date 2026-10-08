-- Raw turtle motion and pose/route commit boundary.
-- Policy, pending-action persistence, and retry decisions belong to callers.
local Pose = require("src.navigation.pose")
local KnownRoute = require("src.fuel.known_route")
local RoutePolicy = require("src.fuel.route_policy")

local Motion = {}

local movementApi = {
    forward = "forward",
    back = "back",
    up = "up",
    down = "down",
}

local function failure(code, message)
    return { ok = false, code = code, message = message, retryable = false }
end

function Motion.move(pose, route, movement, turtleApi)
    local apiName = movementApi[movement]
    if not apiName then return nil, failure("INVALID_MOVEMENT", "Unknown movement direction.") end
    local nextPose, poseStatus = Pose.afterMove(pose, movement, true)
    if not poseStatus.ok then return nil, poseStatus end

    local apiResult = turtleApi[apiName]()
    if apiResult ~= true then return Pose.afterMove(pose, movement, apiResult) end

    local updated, result = Pose.afterMove(pose, movement, true)
    if not result.ok then return nil, result end
    if route then
        local recorded, reason = KnownRoute.recordMove(route, pose, updated)
        if not recorded then return nil, failure("ROUTE_RECORD_FAILED", tostring(reason)) end
    end
    return updated, { ok = true, code = "MOVE_COMMITTED" }
end

function Motion.moveWithPolicy(pose, route, movement, turtleApi, policy)
    local allowed, reason = RoutePolicy.canMove({
        pose = pose,
        route = route,
        movement = movement,
        reserve = policy.reserve,
        getFuelLevel = policy.getFuelLevel,
        refuel = policy.refuel,
    })
    if not allowed then
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
