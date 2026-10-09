local Landing = require("src.navigation.floor_landing")
local Pose = require("src.navigation.pose")
local Result = require("src.safety.result")

local pose = { x = 0, y = -8, z = -12, facing = 0 }
local cleared = {}
local actions = 0

local function target(direction)
    local base = { x = pose.x, y = pose.y, z = pose.z, facing = pose.facing }
    if direction == "forward" or direction == "back" then
        return assert(Pose.afterMove(base, direction, true))
    elseif direction == "up" or direction == "down" then
        return assert(Pose.afterMove(base, direction, true))
    end
    error("unexpected clear direction " .. tostring(direction))
end

local updated, outcome = Landing.prepare({
    pose = pose,
    clear = function(direction)
        local block = target(direction)
        cleared[block.x .. "," .. block.y .. "," .. block.z] = true
        return Result.new(true, "CLEAR_COMPLETE")
    end,
    move = function(direction)
        pose = assert(Pose.afterMove(pose, direction, true))
        actions = actions + 1
        return pose, Result.new(true, "MOVE_COMMITTED")
    end,
    turn = function(direction)
        pose = assert(Pose.afterTurn(pose, direction, true))
        actions = actions + 1
        return pose, Result.new(true, "TURN_COMMITTED")
    end,
})

assert(outcome.ok and outcome.code == "LANDING_CARVED")
assert(updated.x == 0 and updated.y == -8 and updated.z == -13 and updated.facing == 0)
assert(actions > 0)
for _, z in ipairs({ -12, -13, -14 }) do
    for _, x in ipairs({ -1, 0, 1 }) do
        for _, y in ipairs({ -7, -6 }) do
            assert(cleared[x .. "," .. y .. "," .. z], "landing headroom was not cleared")
        end
    end
end
for _, x in ipairs({ -1, 1 }) do
    for _, z in ipairs({ -12, -13, -14 }) do
        assert(cleared[x .. ",-8," .. z], "landing lower side column was not cleared")
    end
end

print("floor landing checks passed")
