local StairRoute = require("src.navigation.stair_route")
local Pose = require("src.navigation.pose")
local Result = require("src.safety.result")

local function move(pose, direction)
    local nextPose, transform = Pose.afterMove(pose, direction, true)
    assert(transform.ok)
    return nextPose, Result.new(true, "MOVE_COMMITTED")
end

local routes = {
    {
        floor = 1,
        origin = { x = 0, y = 0, z = 0, facing = 0 },
        mouth = { x = 0, y = 0, z = -4, facing = 0 },
        rear = { x = 0, y = -8, z = -12, facing = 0 },
        landing = { x = 0, y = -8, z = -13, facing = 0 },
        steps = 8, entryMoves = 4,
    },
    {
        floor = 2,
        origin = { x = 0, y = -8, z = -13, facing = 0 },
        mouth = { x = 0, y = -8, z = -14, facing = 0 },
        rear = { x = 0, y = -16, z = -22, facing = 0 },
        landing = { x = 0, y = -16, z = -23, facing = 0 },
        steps = 8, entryMoves = 1,
    },
}

local pose = { x = 0, y = 0, z = 0, facing = 0 }
local calls, digs = {}, 0
local resumed, outcome = StairRoute.resumeToLanding({
    pose = pose,
    floor = 2,
    routes = routes,
    move = function(direction)
        calls[#calls + 1] = direction
        pose = move(pose, direction)
        return pose, Result.new(true, "MOVE_COMMITTED")
    end,
    turn = function() error("straight stair resume must not turn") end,
    clear = function() digs = digs + 1 error("resume must not dig") end,
})
assert(outcome.ok and outcome.code == "ACTIVE_LANDING_REACHED")
assert(resumed.x == 0 and resumed.y == -16 and resumed.z == -23 and resumed.facing == 0)
assert(#calls == 4 + 8 * 2 + 1 + 1 + 8 * 2 + 1, "resume should replay only recorded centreline moves")
assert(digs == 0)

-- Recorded configured stair intervals are replayable; the route is not tied
-- to the default eight-slice floor depth.
local shortRoute = {
    {
        floor = 1,
        origin = { x = 0, y = 0, z = 0, facing = 0 },
        mouth = { x = 0, y = 0, z = -4, facing = 0 },
        rear = { x = 0, y = -3, z = -7, facing = 0 },
        landing = { x = 0, y = -3, z = -8, facing = 0 },
        steps = 3, entryMoves = 4,
    },
}
local shortPose = { x = 0, y = 0, z = 0, facing = 0 }
local shortCalls = 0
local shortResumed, shortOutcome = StairRoute.resumeToLanding({
    pose = shortPose,
    floor = 1,
    routes = shortRoute,
    move = function(direction)
        shortPose = move(shortPose, direction)
        shortCalls = shortCalls + 1
        return shortPose, Result.new(true, "MOVE_COMMITTED")
    end,
})
assert(shortOutcome.ok and shortOutcome.code == "ACTIVE_LANDING_REACHED")
assert(shortResumed.y == -3 and shortResumed.z == -8)
assert(shortCalls == 4 + 3 * 2 + 1, "resume must use the saved stair step count")

local invalidPose = { x = 0, y = 0, z = 1, facing = 0 }
local _, invalid = StairRoute.resumeToLanding({
    pose = invalidPose, floor = 1, routes = routes,
    move = function() error("invalid origin must fail before moving") end,
    turn = function() end,
})
assert(not invalid.ok and invalid.code == "LANDING_ROUTE_INVALID")

local incompleteMoves = 0
local _, incomplete = StairRoute.resumeToLanding({
    pose = { x = 0, y = 0, z = 0, facing = 0 },
    floor = 2,
    routes = { routes[1] },
    move = function()
        incompleteMoves = incompleteMoves + 1
        error("incomplete route must fail before moving")
    end,
})
assert(not incomplete.ok and incomplete.code == "LANDING_ROUTE_INVALID")
assert(incompleteMoves == 0, "all requested floor routes must validate before departure")

local blockedPose = { x = 0, y = 0, z = 0, facing = 0 }
local blockedMoves = 0
local _, blocked = StairRoute.resumeToLanding({
    pose = blockedPose,
    floor = 1,
    routes = routes,
    move = function(direction)
        blockedMoves = blockedMoves + 1
        if blockedMoves == 3 then
            return blockedPose, Result.new(false, "RETURN_BLOCKED")
        end
        blockedPose = move(blockedPose, direction)
        return blockedPose, Result.new(true, "MOVE_COMMITTED")
    end,
})
assert(not blocked.ok and blocked.code == "RETURN_BLOCKED")
assert(blockedMoves == 3, "failed inverse route movement must stop immediately")

local malformedRoutes = {
    {
        floor = 1,
        origin = routes[1].origin,
        mouth = routes[1].mouth,
        rear = routes[1].rear,
        landing = { x = 0, y = -8, z = -14, facing = 0 },
        steps = 8,
        entryMoves = 4,
    },
}
local malformedMoves = 0
local _, malformed = StairRoute.resumeToLanding({
    pose = { x = 0, y = 0, z = 0, facing = 0 },
    floor = 1,
    routes = malformedRoutes,
    move = function()
        malformedMoves = malformedMoves + 1
        error("malformed route geometry must fail before moving")
    end,
})
assert(not malformed.ok and malformed.code == "LANDING_ROUTE_INVALID")
assert(malformedMoves == 0, "route geometry must validate before departure")

local malformedSecondFloor = {
    routes[1],
    {
        floor = 2,
        origin = routes[2].origin,
        mouth = routes[2].mouth,
        rear = routes[2].rear,
        landing = { x = 0, y = -16, z = -24, facing = 0 },
        steps = 8,
        entryMoves = 1,
    },
}
local laterFloorMoves = 0
local _, laterMalformed = StairRoute.resumeToLanding({
    pose = { x = 0, y = 0, z = 0, facing = 0 },
    floor = 2,
    routes = malformedSecondFloor,
    move = function()
        laterFloorMoves = laterFloorMoves + 1
        error("later malformed floor must fail before descent")
    end,
})
assert(not laterMalformed.ok and laterMalformed.code == "LANDING_ROUTE_INVALID")
assert(laterFloorMoves == 0, "all floor records must validate before the first move")
print("stair resume checks passed")
