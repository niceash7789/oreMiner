local ReturnMove = require("src.navigation.return_move")
local KnownRoute = require("src.fuel.known_route")

local home = { x = 0, y = 0, z = 0, facing = 0 }
local nextPose = { x = 0, y = 0, z = -1, facing = 0 }
local route = assert(KnownRoute.new(home))
assert(KnownRoute.recordMove(route, home, nextPose))

local moveCalls, digCalls = 0, 0
local success = ReturnMove.run({
    hasEdge = function() return KnownRoute.hasEdge(route, nextPose, home) end,
    move = function() moveCalls = moveCalls + 1; return true end,
    maxAttempts = 3,
})
assert(success.ok and success.attempts == 1)
assert(moveCalls == 1 and digCalls == 0, "return travel must move on recorded edge without digging")

moveCalls = 0
local blocked = ReturnMove.run({
    hasEdge = function() return KnownRoute.hasEdge(route, nextPose, home) end,
    move = function() moveCalls = moveCalls + 1; return false end,
    maxAttempts = 3,
    recover = function() end,
})
assert(not blocked.ok and blocked.code == "RETURN_BLOCKED" and blocked.attempts == 3)
assert(moveCalls == 3, "persistent obstruction must stop after bounded recovery")

local unknown = ReturnMove.run({
    hasEdge = function() return false end,
    move = function() error("unknown route must not move") end,
    maxAttempts = 3,
})
assert(not unknown.ok and unknown.code == "RETURN_ROUTE_UNKNOWN")
assert(digCalls == 0)

print("return movement checks passed")
