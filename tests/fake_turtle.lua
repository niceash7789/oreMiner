-- Deterministic movement double for navigation pose tests.
-- This models only position/facing and the boolean result from the turtle API.
local FakeTurtle = {}
FakeTurtle.__index = FakeTurtle

local function copyPose(pose)
    return { x = pose.x, y = pose.y, z = pose.z, facing = pose.facing }
end

function FakeTurtle.new(pose)
    return setmetatable({ pose = copyPose(pose) }, FakeTurtle)
end

function FakeTurtle:move(movement, apiResult)
    if apiResult ~= true then
        return apiResult
    end

    local pose = self.pose
    if movement == "up" then
        pose.y = pose.y + 1
    elseif movement == "down" then
        pose.y = pose.y - 1
    elseif movement == "forward" or movement == "back" then
        local sign = movement == "forward" and 1 or -1
        if pose.facing == 0 then
            pose.z = pose.z - sign
        elseif pose.facing == 1 then
            pose.x = pose.x + sign
        elseif pose.facing == 2 then
            pose.z = pose.z + sign
        else
            pose.x = pose.x - sign
        end
    else
        error("unsupported fake movement: " .. tostring(movement))
    end

    return true
end

function FakeTurtle:turn(direction, apiResult)
    if apiResult ~= true then
        return apiResult
    end
    if direction == "left" then
        self.pose.facing = (self.pose.facing - 1) % 4
    elseif direction == "right" then
        self.pose.facing = (self.pose.facing + 1) % 4
    else
        error("unsupported fake turn: " .. tostring(direction))
    end
    return true
end

return FakeTurtle
