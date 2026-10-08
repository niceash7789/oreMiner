-- Checked turtle turn adapter used by the active coordinator.
local Pose = require("src.navigation.pose")

local Turn = {}

function Turn.run(pose, direction, turtleApi)
    if direction ~= "left" and direction ~= "right" then
        return nil, { ok = false, code = "INVALID_TURN", message = "Turn direction must be left or right.", retryable = false }
    end
    local action = direction == "left" and turtleApi.turnLeft or turtleApi.turnRight
    local apiResult = action()
    return Pose.afterTurn(pose, direction, apiResult)
end

-- Apply the shortest checked turn sequence and retain each committed pose.
-- applyTurn must return the pose produced by the coordinator's checked turn
-- boundary plus its outcome, so persistence failures still expose known pose.
function Turn.face(pose, targetFacing, applyTurn)
    if type(targetFacing) ~= "number" or targetFacing ~= math.floor(targetFacing)
        or targetFacing < 0 or targetFacing > 3 then
        return pose, { ok = false, code = "INVALID_FACING", message = "Target facing must be an integer from 0 to 3.", retryable = false }
    end
    if type(applyTurn) ~= "function" then
        return pose, { ok = false, code = "INVALID_TURN_CALLBACK", message = "A checked turn callback is required.", retryable = false }
    end
    if type(pose) ~= "table" or type(pose.facing) ~= "number"
        or pose.facing ~= math.floor(pose.facing) or pose.facing < 0 or pose.facing > 3 then
        return pose, { ok = false, code = "INVALID_POSE", message = "Cannot face from an invalid pose.", retryable = false }
    end

    local delta = (targetFacing - pose.facing) % 4
    local directions = delta == 1 and { "right" }
        or delta == 2 and { "right", "right" }
        or delta == 3 and { "left" }
        or {}
    local current = pose
    for _, direction in ipairs(directions) do
        local expectedFacing = (current.facing + (direction == "right" and 1 or 3)) % 4
        local updated, result = applyTurn(direction)
        if type(updated) == "table" then current = updated end
        if type(result) ~= "table" or result.ok ~= true then
            return current, result or {
                ok = false,
                code = "TURN_FAILED",
                message = "Checked turn did not succeed.",
                retryable = false,
            }
        end
        if current.facing ~= expectedFacing then
            return current, { ok = false, code = "POSE_MISMATCH", message = "Checked turn returned an unexpected facing.", retryable = false }
        end
    end
    if current.facing ~= targetFacing then
        return current, { ok = false, code = "POSE_MISMATCH", message = "Checked turns did not reach the target facing.", retryable = false }
    end
    return current, { ok = true, code = "FACING_REACHED", turns = #directions }
end

return Turn
