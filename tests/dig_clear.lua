local DigClear = require("src.safety.dig_clear")

local function scenario(blocks, options)
    local state = { blocks = blocks, time = 0, digs = 0 }
    options.detect = function() return state.blocks > 0 end
    options.dig = function()
        state.digs = state.digs + 1
        if state.blocks > 0 then state.blocks = state.blocks - 1 end
        return true
    end
    options.now = function() return state.time end
    options.wait = function() state.time = state.time + (options.waitStep or 0) end
    options.waitStep = nil
    return DigClear.run(options), state
end

local result = scenario(2, { maxAttempts = 4, maxElapsed = 3 })
assert(result.ok and result.code == "NO_BLOCK" and result.attempts == 2 and result.dug == 2)

local empty = scenario(0, { maxAttempts = 4, maxElapsed = 3 })
assert(empty.ok and empty.code == "NO_BLOCK" and empty.dug == 0,
    "an empty cell is a successful no-op")

local unbreakable = DigClear.run({
    detect = function() return true end,
    dig = function() return false end,
    now = function() return 0 end,
    maxAttempts = 4,
    maxElapsed = 3,
})
assert(not unbreakable.ok and unbreakable.code == "UNBREAKABLE_BLOCK",
    "failed dig must remain a distinct safety error")

result = scenario(8, { maxAttempts = 2, maxElapsed = 5 })
assert(not result.ok and result.code == "DIG_ATTEMPTS_EXHAUSTED" and result.attempts == 2)

local state = { blocks = 8, time = 0, digs = 0 }
result = DigClear.run({
    maxAttempts = 10,
    maxElapsed = 1,
    detect = function() return state.blocks > 0 end,
    dig = function() state.blocks = state.blocks - 1; state.digs = state.digs + 1; return true end,
    now = function() return state.time end,
    wait = function() state.time = state.time + 0.6 end,
})
assert(not result.ok and result.code == "DIG_TIME_EXHAUSTED" and result.attempts == 2)

print("dig_clear: ok")
