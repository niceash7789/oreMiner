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

return Turn
