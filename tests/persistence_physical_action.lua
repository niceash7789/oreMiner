local PhysicalAction = require("src.persistence.physical_action")

local calls = {}
local session = {}
function session:beginAction(kind, direction)
    calls[#calls + 1] = "intent:" .. kind .. ":" .. direction
    return true
end
function session:commitAction()
    calls[#calls + 1] = "commit"
    return true
end
function session:cancelAction()
    calls[#calls + 1] = "cancel"
    return true
end

local pose, route, config = { x = 0, y = 0, z = 0, facing = 0 }, {}, {}
local outcome = PhysicalAction.run(session, "dig", "forward", pose, route, config, function()
    calls[#calls + 1] = "physical"
    return true
end)
assert(outcome.ok and outcome.code == "ACTION_COMMITTED")
assert(table.concat(calls, ",") == "intent:dig:forward,physical,commit",
    "durable dig intent must precede the turtle call and commit must follow success")

calls = {}
outcome = PhysicalAction.run(session, "dig", "up", pose, route, config, function()
    calls[#calls + 1] = "physical"
    return false
end)
assert(not outcome.ok and outcome.code == "DIG_FAILED")
assert(table.concat(calls, ",") == "intent:dig:up,physical,cancel",
    "literal API failure cancels the intent without committing")

calls = {}
outcome = PhysicalAction.run(session, "dig", "down", pose, route, config, function()
    calls[#calls + 1] = "physical"
    error("simulated interruption")
end)
assert(not outcome.ok and outcome.code == "ACTION_RESULT_UNCERTAIN")
assert(table.concat(calls, ",") == "intent:dig:down,physical",
    "an exception after intent must preserve uncertainty and never cancel it")

calls = {}
function session:commitAction() calls[#calls + 1] = "commit"; return false, "STATE_WRITE_FAILED" end
outcome = PhysicalAction.run(session, "dig", "forward", pose, route, config, function()
    calls[#calls + 1] = "physical"
    return true
end)
assert(not outcome.ok and outcome.code == "STATE_WRITE_FAILED")
assert(table.concat(calls, ",") == "intent:dig:forward,physical,commit",
    "failed commit must stop after the physical action without clearing durable intent")

calls = {}
function session:beginAction() calls[#calls + 1] = "intent"; return false, "STATE_WRITE_FAILED" end
outcome = PhysicalAction.run(session, "dig", "forward", pose, route, config, function()
    error("must not invoke after failed intent")
end)
assert(not outcome.ok and outcome.code == "STATE_WRITE_FAILED" and #calls == 1)

print("persistence_physical_action: ok")
