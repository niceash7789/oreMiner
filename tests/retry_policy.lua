local Retry = require("src.safety.retry")
local defaults = require("src.config.defaults")

assert(defaults.safety.moveRetries == 5)
assert(defaults.safety.digRetries == 12)
assert(defaults.safety.entityRetries == 5)

local calls = 0
local recovered = Retry.run(3, "BLOCKED", function()
    calls = calls + 1
    if calls < 3 then
        return Retry.result(false, "MOVE_FAILED", "temporarily blocked", true)
    end
    return Retry.result(true, "OK", "cleared", false)
end)
assert(recovered.ok and recovered.attempts == 3 and calls == 3)

calls = 0
local exhausted = Retry.run(2, "ENTITY_BLOCKED", function()
    calls = calls + 1
    return Retry.result(false, "ENTITY_PRESENT", "occupied", true)
end)
assert(not exhausted.ok and exhausted.code == "ENTITY_BLOCKED")
assert(exhausted.attempts == 2 and calls == 2 and not exhausted.retryable)

calls = 0
local terminal = Retry.run(4, "BLOCKED", function()
    calls = calls + 1
    return Retry.result(false, "UNBREAKABLE_BLOCK", "protected", false)
end)
assert(not terminal.ok and terminal.code == "UNBREAKABLE_BLOCK")
assert(terminal.attempts == 1 and calls == 1)

assert(Retry.run(0, "BLOCKED", function() error("must not run") end).code == "INVALID_RETRY_POLICY")
assert(Retry.run(65, "BLOCKED", function() error("must not run") end).code == "INVALID_RETRY_POLICY")

print("retry policy tests passed")
