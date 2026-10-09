-- Canonical floor main-shaft segment geometry from a recorded landing.
local MainShaft = {}

local function isInteger(value)
    return type(value) == "number" and value == math.floor(value)
end

local function copy(pose)
    return { x = pose.x, y = pose.y, z = pose.z, facing = pose.facing }
end

local function failure(code)
    return { ok = false, code = code, retryable = false }
end

local function same(left, right)
    return left.x == right.x and left.y == right.y and left.z == right.z
        and left.facing == right.facing
end

function MainShaft.new(landingPose, mainFacing, length)
    if type(landingPose) ~= "table" or not isInteger(landingPose.x)
        or not isInteger(landingPose.y) or not isInteger(landingPose.z)
        or not isInteger(landingPose.facing) or landingPose.facing < 0
        or landingPose.facing > 3 or not isInteger(mainFacing)
        or mainFacing < 0 or mainFacing > 3 or (mainFacing - landingPose.facing) % 4 ~= 1 then
        return nil, failure("INVALID_MAIN_SHAFT_ORIGIN")
    end
    if not isInteger(length) or length < 1 then return nil, failure("INVALID_MAIN_SHAFT_LENGTH") end

    local shaft = { origin = copy(landingPose), facing = mainFacing, length = length }
    shaft.origin.facing = mainFacing

    function shaft.pose(offset)
        if not isInteger(offset) or offset < 0 or offset > shaft.length then
            return nil, failure("INVALID_MAIN_SHAFT_OFFSET")
        end
        local pose = copy(shaft.origin)
        if mainFacing == 0 then pose.z = pose.z - offset
        elseif mainFacing == 1 then pose.x = pose.x + offset
        elseif mainFacing == 2 then pose.z = pose.z + offset
        else pose.x = pose.x - offset end
        return pose, { ok = true, code = "MAIN_SHAFT_POSE" }
    end

    function shaft.isCanonicalReturn(pose)
        return same(pose, shaft.origin)
    end

    return shaft, { ok = true, code = "MAIN_SHAFT_CREATED" }
end

return MainShaft
