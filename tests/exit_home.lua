local ExitHome = require("src.safety.exit_home")

assert(ExitHome.isTermination("Terminated"))
assert(ExitHome.isTermination("src/branch_miner.lua:42: Terminated"))
assert(not ExitHome.isTermination("Fuel Terminated"))
assert(not ExitHome.isTermination("MOVE_FAILED"))

local messages = {}
local started = false
local ok = ExitHome.run(function() started = true end,
    function(message) messages[#messages + 1] = message end)
assert(ok and started and #messages == 1)

ok = ExitHome.run(function() error("POSITION_UNCERTAIN") end,
    function(message) messages[#messages + 1] = message end)
assert(not ok and messages[#messages]:find("POSITION_UNCERTAIN", 1, true),
    "a failed home command must report the safe stop")

local events = { { "terminate" }, { "unrelated" }, { "turtle_response", true } }
local index = 0
local stopRequested = false
local actionFinished = false
local completed, value = ExitHome.runActive(function()
    local event, success = coroutine.yield("turtle_response")
    assert(event == "turtle_response" and success == true)
    actionFinished = true
    assert(stopRequested, "exit should already be requested")
end, function()
    index = index + 1
    return table.unpack(events[index])
end, function() stopRequested = true end)
assert(completed and value == nil and actionFinished and index == 3,
    "terminate should be withheld while the pending turtle action completes")

print("exit home checks passed")
