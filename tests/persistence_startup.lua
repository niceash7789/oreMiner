local Startup = require("src.persistence.startup")

local missing = Startup.newRunDecision(nil, "STATE_MISSING")
assert(missing.start == true, "an absent snapshot should allow a new run")

local complete = Startup.newRunDecision({ status = function() return "complete" end }, "STATE_LOADED")
assert(complete.start == true, "a completed snapshot should allow a new run")

local active = Startup.newRunDecision({ status = function() return "mining" end }, "STATE_LOADED")
assert(active.start == false and active.message:find("ACTIVE_STATE_PRESENT", 1, true))
assert(active.message:find("miner status", 1, true)
    and active.message:find("miner resume", 1, true)
    and active.message:find("manual reconciliation", 1, true),
    "active state should print actionable recovery guidance")

for _, code in ipairs({ "POSITION_UNCERTAIN", "STATE_CORRUPT", "CONFIG_MISMATCH" }) do
    local decision = Startup.newRunDecision(nil, code)
    assert(decision.start == false and decision.message:find(code, 1, true),
        "unsafe load result must still refuse a new run: " .. code)
end

print("persistence startup checks passed")
