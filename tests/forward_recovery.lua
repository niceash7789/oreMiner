local ForwardRecovery = require("src.safety.forward_recovery")
local Result = require("src.safety.result")

local moves, attacks, waits = 0, 0, 0
local result = ForwardRecovery.run({
    move = function()
        moves = moves + 1
        return moves == 3
    end,
    detect = function() return false end,
    digClear = function() error("entity path must not dig") end,
    attack = function() attacks = attacks + 1; return true end,
    wait = function() waits = waits + 1 end,
    maxMoveRetries = 2,
    maxEntityRetries = 3,
})
assert(result.ok and result.entityRetries == 2 and moves == 3)
assert(attacks == 2 and waits == 2, "transient entity recovery should attack and wait within budget")

moves, attacks, waits = 0, 0, 0
result = ForwardRecovery.run({
    move = function() moves = moves + 1; return false end,
    detect = function() return false end,
    digClear = function() error("entity path must not dig") end,
    attack = function() attacks = attacks + 1; return false end,
    wait = function() waits = waits + 1 end,
    maxMoveRetries = 2,
    maxEntityRetries = 3,
})
assert(not result.ok and result.code == "ENTITY_BLOCKED" and result.entityRetries == 3)
assert(moves == 4 and attacks == 3 and waits == 3, "persistent entities must stop at the exact retry limit")

moves = 0
local clears = 0
result = ForwardRecovery.run({
    move = function() moves = moves + 1; return moves == 2 end,
    detect = function() return true end,
    digClear = function() clears = clears + 1; return Result.new(true, "NO_BLOCK") end,
    attack = function() error("solid block path must not attack") end,
    wait = function() end,
    maxMoveRetries = 2,
    maxEntityRetries = 2,
})
assert(result.ok and result.moveRetries == 1 and clears == 1 and moves == 2,
    "solid obstruction should use bounded dig-clear before retrying movement")

local digFailure = Result.new(false, "UNBREAKABLE_BLOCK")
result = ForwardRecovery.run({
    move = function() return false end,
    detect = function() return true end,
    digClear = function() return digFailure end,
    attack = function() error("unbreakable solid must not trigger entity attack") end,
    wait = function() end,
    maxMoveRetries = 2,
    maxEntityRetries = 2,
})
assert(result == digFailure, "dig-clear failure should propagate unchanged")

moves, clears, attacks = 0, 0, 0
result = ForwardRecovery.run({
    move = function() moves = moves + 1; return false end,
    detect = function() return true end,
    digClear = function() clears = clears + 1; return Result.new(true, "NO_BLOCK") end,
    attack = function() attacks = attacks + 1 end,
    wait = function() end,
    maxMoveRetries = 2,
    maxEntityRetries = 2,
})
assert(not result.ok and result.code == "BLOCKED" and moves == 3 and clears == 2,
    "repeated solid obstructions must stop at the movement recovery bound")
assert(attacks == 0, "solid blocks must never be treated as entities")

local fuelDenied = Result.new(false, "INSUFFICIENT_FUEL")
local inspected = false
result = ForwardRecovery.run({
    move = function() return false, fuelDenied end,
    detect = function() inspected = true; return false end,
    digClear = function() error("denied movement must not dig") end,
    attack = function() error("denied movement must not attack") end,
    wait = function() error("denied movement must not wait") end,
    maxMoveRetries = 2,
    maxEntityRetries = 2,
})
assert(result == fuelDenied and not inspected,
    "fuel or persistence denial must stop before obstruction recovery")

result = ForwardRecovery.run({
    move = function() return "failed" end,
    detect = function() error("malformed movement must stop before inspect") end,
    digClear = function() error("malformed movement must stop before dig") end,
    attack = function() error("malformed movement must stop before attack") end,
    wait = function() end,
    maxMoveRetries = 2,
    maxEntityRetries = 2,
})
assert(not result.ok and result.code == "INVALID_MOVE_OUTCOME")

local moveCalls = 0
result = ForwardRecovery.run({
    move = function() moveCalls = moveCalls + 1; return false end,
    detect = function() return "unknown" end,
    digClear = function() error("invalid detection must stop before dig") end,
    attack = function() error("invalid detection must stop before attack") end,
    wait = function() end,
    maxMoveRetries = 2,
    maxEntityRetries = 2,
})
assert(not result.ok and result.code == "INVALID_DETECTION_OUTCOME" and moveCalls == 1)

print("forward_recovery: ok")
