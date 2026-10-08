-- Reversible physical-action records for bounded local route unwind.
local Result = require("src.safety.result")

local ActionStack = {}

local inverseByAction = {
    forward = "back",
    back = "forward",
    up = "down",
    down = "up",
    turnLeft = "turnRight",
    turnRight = "turnLeft",
}

function ActionStack.inverse(action)
    return inverseByAction[action]
end

function ActionStack.new()
    return { records = {} }
end

function ActionStack.record(stack, action)
    local inverse = ActionStack.inverse(action)
    if type(stack) ~= "table" or type(stack.records) ~= "table" or not inverse then
        return Result.new(false, "INVALID_ROUTE_ACTION", "Route action is not reversible.")
    end

    stack.records[#stack.records + 1] = {
        action = action,
        inverse = inverse,
    }
    return Result.new(true, "ROUTE_ACTION_RECORDED", "Reversible route action recorded.", {
        depth = #stack.records,
    })
end

function ActionStack.unwind(stack, applyInverse)
    if type(stack) ~= "table" or type(stack.records) ~= "table"
        or type(applyInverse) ~= "function" then
        return Result.new(false, "INVALID_ROUTE_STACK", "A route stack and inverse-action callback are required.")
    end

    while #stack.records > 0 do
        local record = stack.records[#stack.records]
        if applyInverse(record.inverse, record.action) ~= true then
            return Result.new(false, "ROUTE_UNWIND_FAILED", "Inverse route action failed.", {
                action = record.inverse,
                remaining = #stack.records,
            })
        end
        stack.records[#stack.records] = nil
    end

    return Result.new(true, "ROUTE_UNWOUND", "Route stack unwound.", { remaining = 0 })
end

return ActionStack
