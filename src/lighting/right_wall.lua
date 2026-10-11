-- Places a torch in the wall defined as right by the route's outbound frame.
-- The caller supplies checked navigation and mining callbacks; this module
-- always returns to the starting pose and facing before reporting success.
local Turn = require("src.navigation.turn")
local Result = require("src.safety.result")

local Lighting = {}

local function validFacing(facing)
    return type(facing) == "number" and facing == math.floor(facing)
        and facing >= 0 and facing <= 3
end

-- Return the cardinal heading and adjacent cell on the route-defined right.
-- This is independent of the turtle's current facing during return travel.
function Lighting.rightSide(pose, outboundFacing)
    if type(pose) ~= "table" or type(pose.x) ~= "number"
        or type(pose.y) ~= "number" or type(pose.z) ~= "number"
        or not validFacing(outboundFacing) then
        return nil, "LIGHTING_INVALID_FRAME"
    end
    local facing = (outboundFacing + 1) % 4
    local result = { x = pose.x, y = pose.y, z = pose.z, facing = facing }
    if facing == 0 then result.z = result.z - 1
    elseif facing == 1 then result.x = result.x + 1
    elseif facing == 2 then result.z = result.z + 1
    else result.x = result.x - 1 end
    return result
end

local function samePose(left, right)
    return left and right and left.x == right.x and left.y == right.y
        and left.z == right.z and left.facing == right.facing
end

function Lighting.placeRight(ops)
    if type(ops) ~= "table" or type(ops.pose) ~= "table"
        or not validFacing(ops.outboundFacing)
        or type(ops.turn) ~= "function"
        or (ops.alreadyClear ~= true and type(ops.dig) ~= "function")
        or type(ops.place) ~= "function" then
        return Result.new(false, "LIGHTING_INVALID_OPTIONS")
    end

    local start = { x = ops.pose.x, y = ops.pose.y, z = ops.pose.z, facing = ops.pose.facing }
    local right = Lighting.rightSide(start, ops.outboundFacing)
    local rightFacing = right.facing
    local facing, turnResult = Turn.face(start, rightFacing, ops.turn)
    if not turnResult.ok then return turnResult end

    if ops.alreadyClear ~= true then
        local dug = ops.dig()
        if type(dug) ~= "table" or dug.ok ~= true then
            local restored, restoreResult = Turn.face(facing, start.facing, ops.turn)
            if not restoreResult.ok then return Result.new(false, "LIGHTING_RESTORE_FAILED", nil, { cause = restoreResult.code }) end
            return type(dug) == "table" and dug or Result.new(false, "LIGHTING_DIG_FAILED")
        end
    end

    local placed = ops.place()
    local restored, restoreResult = Turn.face(facing, start.facing, ops.turn)
    if not restoreResult.ok then
        return Result.new(false, "LIGHTING_RESTORE_FAILED", nil, { cause = restoreResult.code })
    end
    if not samePose(restored, start) then return Result.new(false, "LIGHTING_POSE_MISMATCH") end
    if type(ops.poseNow) == "function" then
        local actual = ops.poseNow()
        if not samePose(actual, start) then
            return Result.new(false, "LIGHTING_POSE_MISMATCH")
        end
    end
    if type(placed) ~= "table" or placed.ok ~= true then
        return type(placed) == "table" and placed or Result.new(false, "TORCH_PLACE_FAILED")
    end
    return Result.new(true, "TORCH_PLACED")
end

return Lighting
