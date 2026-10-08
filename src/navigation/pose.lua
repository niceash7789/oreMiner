-- Pure pose transformations for the single-turtle navigation layer.
-- Callers commit the returned pose only after the turtle API reports success.
-- Facing is 0=north/-z, 1=east/+x, 2=south/+z, 3=west/-x.

local Pose = {}

local function isInteger(value)
    return type(value) == "number" and value == math.floor(value)
end

local function copy(pose)
    return {
        x = pose.x,
        y = pose.y,
        z = pose.z,
        facing = pose.facing,
    }
end

local function validPose(pose)
    return type(pose) == "table"
        and isInteger(pose.x)
        and isInteger(pose.y)
        and isInteger(pose.z)
        and isInteger(pose.facing)
        and pose.facing >= 0
        and pose.facing <= 3
end

local function failure(code, message)
    return {
        ok = false,
        code = code,
        message = message,
        retryable = false,
    }
end

function Pose.new(x, y, z, facing)
    local pose = {
        x = x or 0,
        y = y or 0,
        z = z or 0,
        facing = facing or 0,
    }

    if not validPose(pose) then
        return nil, failure("INVALID_POSE", "Pose coordinates must be integers and facing must be 0..3.")
    end

    return pose, { ok = true, code = "POSE_CREATED" }
end

-- Returns a new pose. The input pose is never modified.
function Pose.afterMove(pose, movement, succeeded)
    if not validPose(pose) then
        return nil, failure("INVALID_POSE", "Cannot move from an invalid pose.")
    end

    local updated = copy(pose)
    if succeeded ~= true then
        return updated, failure("MOVE_FAILED", "Pose unchanged because the turtle movement failed.")
    end

    if movement == "up" then
        updated.y = updated.y + 1
    elseif movement == "down" then
        updated.y = updated.y - 1
    elseif movement == "forward" or movement == "back" then
        local sign = movement == "forward" and 1 or -1
        if pose.facing == 0 then
            updated.z = updated.z - sign
        elseif pose.facing == 1 then
            updated.x = updated.x + sign
        elseif pose.facing == 2 then
            updated.z = updated.z + sign
        else
            updated.x = updated.x - sign
        end
    else
        return nil, failure("INVALID_MOVEMENT", "Movement must be forward, back, up, or down.")
    end

    return updated, { ok = true, code = "POSE_MOVED" }
end

-- Returns a new pose. The input pose is never modified.
function Pose.afterTurn(pose, direction, succeeded)
    if not validPose(pose) then
        return nil, failure("INVALID_POSE", "Cannot turn from an invalid pose.")
    end

    if direction ~= "left" and direction ~= "right" then
        return nil, failure("INVALID_TURN", "Turn direction must be left or right.")
    end

    local updated = copy(pose)
    if succeeded ~= true then
        return updated, failure("TURN_FAILED", "Facing unchanged because the turtle turn failed.")
    end

    local delta = direction == "right" and 1 or -1
    -- Lua's modulo behavior differs by version for negative dividends. Shift
    -- into a non-negative range before taking the remainder.
    updated.facing = ((updated.facing + delta) % 4 + 4) % 4
    return updated, { ok = true, code = "POSE_TURNED" }
end

return Pose
