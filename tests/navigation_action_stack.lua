local ActionStack = require("src.navigation.action_stack")

local expected = {
    forward = "back",
    back = "forward",
    up = "down",
    down = "up",
    turnLeft = "turnRight",
    turnRight = "turnLeft",
}
for action, inverse in pairs(expected) do
    assert(ActionStack.inverse(action) == inverse, action .. " inverse must be explicit")
end
assert(ActionStack.inverse("dig") == nil, "non-route actions must not acquire an inverse")

local stack = ActionStack.new()
assert(ActionStack.record(stack, "forward").ok)
assert(ActionStack.record(stack, "turnRight").ok)
assert(ActionStack.record(stack, "up").ok)

local applied = {}
local result = ActionStack.unwind(stack, function(action)
    applied[#applied + 1] = action
    return true
end)
assert(result.ok and result.code == "ROUTE_UNWOUND" and #stack.records == 0)
assert(table.concat(applied, ",") == "down,turnLeft,back", "unwind must be strict LIFO")

stack = ActionStack.new()
assert(ActionStack.record(stack, "forward").ok)
assert(ActionStack.record(stack, "turnRight").ok)
assert(ActionStack.record(stack, "up").ok)
result = ActionStack.unwind(stack, function(action)
    return action ~= "turnLeft"
end)
assert(not result.ok and result.code == "ROUTE_UNWIND_FAILED")
assert(result.action == "turnLeft" and result.remaining == 2)
assert(#stack.records == 2 and stack.records[2].action == "turnRight",
    "a failed inverse must remain recorded for safe operator recovery")

local depth = #stack.records
result = ActionStack.record(stack, "dig")
assert(not result.ok and result.code == "INVALID_ROUTE_ACTION" and #stack.records == depth)

print("navigation action stack checks passed")
