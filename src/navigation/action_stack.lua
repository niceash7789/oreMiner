-- Reversible physical-action records for bounded local route unwind.
local Result = require("src.safety.result")

local ActionStack = {}
local MAX_RECORDS = 100000

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

function ActionStack.validate(stack)
    if type(stack) ~= "table" or type(stack.records) ~= "table" then return false end
    local count = 0
    for index, record in pairs(stack.records) do
        count = count + 1
        if type(index) ~= "number" or index ~= math.floor(index) or index < 1
            or index > MAX_RECORDS or type(record) ~= "table"
            or ActionStack.inverse(record.action) ~= record.inverse then
            return false
        end
    end
    if count ~= #stack.records then return false end
    return #stack.records <= MAX_RECORDS
end

function ActionStack.record(stack, action)
    local inverse = ActionStack.inverse(action)
    if not ActionStack.validate(stack) or not inverse then
        return Result.new(false, "INVALID_ROUTE_ACTION", "Route action is not reversible.")
    end
    if #stack.records >= MAX_RECORDS then
        return Result.new(false, "ROUTE_STACK_LIMIT", "Route stack reached its safety limit.")
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
        local outcome = applyInverse(record.inverse, record.action)
        -- A structured success is accepted for checked coordinator callbacks;
        -- bare callbacks retain the original literal-true contract.
        local succeeded = outcome == true or type(outcome) == "table" and outcome.ok == true
        if not succeeded then
            return Result.new(false, "ROUTE_UNWIND_FAILED", "Inverse route action failed.", {
                action = record.inverse,
                remaining = #stack.records,
            })
        end
        stack.records[#stack.records] = nil
        if type(stack.persist) == "function" and stack.persist(stack) ~= true then
            -- The physical inverse may have completed, but its removal is not
            -- durable. Stop before attempting another action so recovery cannot
            -- silently skip the uncertain edge.
            stack.records[#stack.records + 1] = record
            return Result.new(false, "ROUTE_STACK_WRITE_FAILED",
                "Inverse completed but route-stack progress could not be saved.", {
                    action = record.inverse,
                    remaining = #stack.records,
                })
        end
    end

    return Result.new(true, "ROUTE_UNWOUND", "Route stack unwound.", { remaining = 0 })
end

function ActionStack.unwindPersisted(stack, applyInverse, persist)
    if type(stack) ~= "table" or type(persist) ~= "function" then
        return Result.new(false, "INVALID_ROUTE_STACK", "A route stack and persistence callback are required.")
    end
    local snapshot = { records = stack.records }
    snapshot.persist = persist
    local result = ActionStack.unwind(snapshot, applyInverse)
    stack.records = snapshot.records
    return result
end

return ActionStack
