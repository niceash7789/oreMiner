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

local overBudget = DigClear.run({
    detect = function() error("invalid policy must not inspect") end,
    dig = function() error("invalid policy must not dig") end,
    now = function() return 0 end,
    maxAttempts = 65,
    maxElapsed = 3,
})
assert(not overBudget.ok and overBudget.code == "INVALID_DIG_CLEAR_POLICY",
    "dig attempts must have a hard upper bound")

local invalidClock = DigClear.run({
    detect = function() error("invalid clock must stop before inspection") end,
    dig = function() error("invalid clock must stop before digging") end,
    now = function() return 0 / 0 end,
    maxAttempts = 4,
    maxElapsed = 3,
})
assert(not invalidClock.ok and invalidClock.code == "INVALID_DIG_CLEAR_CLOCK")

result = scenario(8, { maxAttempts = 2, maxElapsed = 5 })
assert(not result.ok and result.code == "BLOCKED" and result.attempts == 2,
    "a persistent obstruction must stop as BLOCKED at the attempt limit")

local sameBlock = { identity = "minecraft:gravel", remaining = 4 }
result = DigClear.run({
    maxAttempts = 2,
    maxElapsed = 3,
    detect = function() return sameBlock.remaining > 0 end,
    inspect = function() return { name = sameBlock.identity } end,
    dig = function()
        sameBlock.remaining = sameBlock.remaining - 1
        return true
    end,
    now = function() return 0 end,
})
assert(not result.ok and result.code == "BLOCKED" and result.attempts == 2,
    "the same block identity must not reset its retry allowance")

local changingBlocks = { "minecraft:gravel", "minecraft:gravel", "minecraft:sand" }
local changingIndex = 1
result = DigClear.run({
    maxAttempts = 2,
    maxElapsed = 3,
    detect = function() return changingIndex <= #changingBlocks end,
    inspect = function() return { name = changingBlocks[changingIndex] } end,
    dig = function() changingIndex = changingIndex + 1; return true end,
    now = function() return 0 end,
})
assert(result.ok and result.attempts == 3 and result.dug == 3,
    "a changed block identity must reset the per-block retry allowance")

local state = { blocks = 8, time = 0, digs = 0 }
result = DigClear.run({
    maxAttempts = 10,
    maxElapsed = 1,
    detect = function() return state.blocks > 0 end,
    dig = function() state.blocks = state.blocks - 1; state.digs = state.digs + 1; return true end,
    now = function() return state.time end,
    wait = function() state.time = state.time + 0.6 end,
})
assert(not result.ok and result.code == "BLOCKED" and result.attempts == 2,
    "a persistent obstruction must stop as BLOCKED at the time limit")

local blockState = { blocks = { "minecraft:gravel", "minecraft:sand" }, index = 1 }
local observed = {}
result = DigClear.run({
    maxAttempts = 4,
    maxElapsed = 3,
    detect = function() return blockState.index <= #blockState.blocks end,
    inspect = function()
        return { name = blockState.blocks[blockState.index] }
    end,
    dig = function() blockState.index = blockState.index + 1; return true end,
    onBlock = function(name, attempt) observed[#observed + 1] = { name, attempt } end,
    now = function() return 0 end,
})
assert(result.ok and #observed == 2
    and observed[1][1] == "minecraft:gravel" and observed[1][2] == 1
    and observed[2][1] == "minecraft:sand" and observed[2][2] == 2,
    "each successful dig retry must report the block inspected before that dig")

local invalidInspection = DigClear.run({
    maxAttempts = 2,
    maxElapsed = 3,
    detect = function() return true end,
    inspect = function() return false end,
    dig = function() error("invalid inspection must stop before digging") end,
    now = function() return 0 end,
})
assert(not invalidInspection.ok and invalidInspection.code == "INVALID_BLOCK_INSPECTION")

print("dig_clear: ok")
