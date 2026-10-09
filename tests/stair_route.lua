local StairRoute = require("src.navigation.stair_route")
local Landing = require("src.navigation.floor_landing")
local Pose = require("src.navigation.pose")
local Result = require("src.safety.result")

local pose = { x = 0, y = 0, z = 0, facing = 0 }
local turns = 0
local moves = 0
local savedSteps = 0
local savedRoute
local firstRoute
local routesByFloor = {}
local torchSteps = {}
local serviceSteps = {}

local function move(direction)
    local nextPose, outcome = Pose.afterMove(pose, direction, true)
    assert(outcome.ok)
    pose = nextPose
    moves = moves + 1
    return pose, Result.new(true, "MOVE_COMMITTED")
end

local function turn(direction)
    local nextPose, outcome = Pose.afterTurn(pose, direction, true)
    assert(outcome.ok)
    pose = nextPose
    turns = turns + 1
    return pose, Result.new(true, "TURN_COMMITTED")
end

local function clear()
    return Result.new(true, "CLEAR_COMPLETE")
end

local landingPose, outcome = StairRoute.descend({
    pose = pose,
    floor = 1,
    steps = 8,
    move = move,
    turn = turn,
    clear = clear,
    stairTorchInterval = 4,
    placeStairTorch = function(torchPose, step)
        torchSteps[#torchSteps + 1] = step
        assert(torchPose.y == -(step - 1), "torch callback sees pre-descent slice height")
        return Result.new(true, "TORCH_PLACED")
    end,
    saveProgress = function(progress)
        assert(progress.floor == 1 and progress.stairStep == savedSteps + 1)
        assert(progress.nextStep == progress.stairStep + 1)
        savedSteps = savedSteps + 1
        return true, Result.new(true, "PROGRESS_SAVED")
    end,
    afterStep = function(progress)
        assert(progress.pose.y == -progress.stairStep
            and progress.pose.z == -(4 + progress.stairStep),
            "service hook must run at each committed centre-bottom slice")
        assert(progress.nextAction == (progress.stairStep < 8
            and "descend_stair_slice" or "prepare_landing"),
            "service checkpoint must identify the next unfinished stair action")
        serviceSteps[#serviceSteps + 1] = progress.stairStep
        return true, Result.new(true, "SERVICE_COMPLETE")
    end,
    prepareLanding = function(rear)
        assert(rear.x == 0 and rear.y == -8 and rear.z == -12 and rear.facing == 0)
        return Landing.prepare({ pose = rear, move = move, turn = turn, clear = clear })
    end,
    saveLanding = function(route)
        savedRoute = route
        firstRoute = route
        routesByFloor[route.floor] = route
        return true, Result.new(true, "LANDING_SAVED")
    end,
})

assert(outcome.ok and outcome.code == "LANDING_RECORDED")
assert(landingPose.x == 0 and landingPose.y == -8 and landingPose.z == -13)
assert(savedSteps == 8 and savedRoute.floor == 1)
assert(#serviceSteps == 8 and serviceSteps[8] == 8,
    "stair service hook should run at each canonical slice checkpoint")
assert(#torchSteps == 1 and torchSteps[1] == 4,
    "stair torch cadence fires at interval and skips final landing slice")
assert(savedRoute.origin.z == 0 and savedRoute.mouth.z == -4)
assert(savedRoute.rear.z == -12 and savedRoute.landing.z == -13)
assert(turns > 0 and moves > 0)

-- A failed service at a committed slice stops before another descent action.
pose = { x = 0, y = 0, z = 0, facing = 0 }
local beforeFailureMoves = moves
local stoppedPose, stoppedOutcome = StairRoute.descend({
    pose = pose,
    floor = 1,
    steps = 3,
    move = move,
    turn = turn,
    clear = clear,
    afterStep = function(progress)
        if progress.stairStep == 1 then
            return false, Result.new(false, "NO_TORCHES")
        end
        return true, Result.new(true, "SERVICE_COMPLETE")
    end,
    prepareLanding = function(rear)
        return Landing.prepare({ pose = rear, move = move, turn = turn, clear = clear })
    end,
    saveLanding = function() return true, Result.new(true, "LANDING_SAVED") end,
})
assert(not stoppedOutcome.ok and stoppedOutcome.code == "NO_TORCHES")
assert(stoppedPose.y == -1 and stoppedPose.z == -5)
assert(moves > beforeFailureMoves)

-- The failed later descent intentionally leaves the world at its committed
-- failure checkpoint; restore the fixture to test the independent return.
pose = { x = landingPose.x, y = landingPose.y, z = landingPose.z, facing = landingPose.facing }
local returned, returnOutcome = StairRoute.returnToSurface({
    pose = landingPose,
    route = firstRoute,
    move = move,
    turn = turn,
})
assert(returnOutcome.ok and returnOutcome.code == "SURFACE_ORIGIN_RESTORED",
    tostring(returnOutcome.code) .. ": " .. tostring(returnOutcome.message))
assert(returned.x == 0 and returned.y == 0 and returned.z == 0 and returned.facing == 0)
assert(pose.x == 0 and pose.y == 0 and pose.z == 0 and pose.facing == 0)

-- Corrupt saved landmarks are rejected before any physical inverse begins.
local invalidRouteMoves = 0
local invalidRoute = {
    origin = firstRoute.origin,
    mouth = firstRoute.mouth,
    rear = { x = firstRoute.rear.x, y = firstRoute.rear.y, z = firstRoute.rear.z + 1,
        facing = firstRoute.rear.facing },
    landing = firstRoute.landing,
    steps = firstRoute.steps,
    entryMoves = firstRoute.entryMoves,
}
local unchangedPose, invalidRouteOutcome = StairRoute.returnToSurface({
    pose = firstRoute.landing,
    route = invalidRoute,
    move = function()
        invalidRouteMoves = invalidRouteMoves + 1
        error("invalid route must be rejected before movement")
    end,
    turn = turn,
})
assert(not invalidRouteOutcome.ok and invalidRouteOutcome.code == "LANDING_ROUTE_INVALID")
assert(invalidRouteMoves == 0 and unchangedPose.z == firstRoute.landing.z,
    "invalid recorded geometry must not begin return travel")

-- Later floors start at the prior landing centre, cross its front cell, and
-- return to that same landing after climbing the new recorded segment.
pose = { x = 0, y = -8, z = -13, facing = 0 }
local secondLanding, secondOutcome = StairRoute.descend({
    pose = pose,
    floor = 2,
    steps = 8,
    alreadyAtFrontLanding = true,
    move = move,
    turn = turn,
    clear = clear,
    prepareLanding = function(rear)
        assert(rear.x == 0 and rear.y == -16 and rear.z == -22 and rear.facing == 0)
        return Landing.prepare({ pose = rear, move = move, turn = turn, clear = clear })
    end,
    saveLanding = function(route)
        savedRoute = route
        return true, Result.new(true, "LANDING_SAVED")
    end,
})
assert(secondOutcome.ok and secondLanding.y == -16 and secondLanding.z == -23)
assert(savedRoute.origin.y == -8 and savedRoute.origin.z == -13)

local previousLanding, previousOutcome = StairRoute.returnToSurface({
    pose = secondLanding,
    route = savedRoute,
    move = move,
    turn = turn,
})
assert(previousOutcome.ok and previousLanding.y == -8 and previousLanding.z == -13)
assert(pose.x == 0 and pose.y == -8 and pose.z == -13 and pose.facing == 0)

-- Return through the recorded floor 2 segment, then floor 1 and the fixed
-- four-block entry. The composed route must restore the exact base pose.
pose = { x = secondLanding.x, y = secondLanding.y, z = secondLanding.z, facing = secondLanding.facing }
local floorOneLanding, floorTwoReturn = StairRoute.returnToSurface({
    pose = secondLanding,
    route = savedRoute,
    move = move,
    turn = turn,
})
assert(floorTwoReturn.ok and floorTwoReturn.code == "SURFACE_ORIGIN_RESTORED")
assert(floorOneLanding.x == firstRoute.landing.x and floorOneLanding.y == firstRoute.landing.y
    and floorOneLanding.z == firstRoute.landing.z and floorOneLanding.facing == firstRoute.landing.facing)
assert(pose.x == floorOneLanding.x and pose.y == floorOneLanding.y
    and pose.z == floorOneLanding.z and pose.facing == floorOneLanding.facing)

local basePose, floorOneReturn = StairRoute.returnToSurface({
    pose = floorOneLanding,
    route = firstRoute,
    move = move,
    turn = turn,
})
assert(floorOneReturn.ok and floorOneReturn.code == "SURFACE_ORIGIN_RESTORED")
assert(basePose.x == 0 and basePose.y == 0 and basePose.z == 0 and basePose.facing == 0)
assert(pose.x == 0 and pose.y == 0 and pose.z == 0 and pose.facing == 0)

-- A failed move on the deeper return route stops immediately and never tries
-- to continue through the upper floor or surface entry.
local blockedPose = { x = secondLanding.x, y = secondLanding.y, z = secondLanding.z, facing = secondLanding.facing }
local failedMoves = 0
local _, blockedReturn = StairRoute.returnToSurface({
    pose = secondLanding,
    route = savedRoute,
    move = function(direction)
        failedMoves = failedMoves + 1
        if failedMoves == 4 then
            return blockedPose, Result.new(false, "INVERSE_BLOCKED")
        end
        local nextPose = assert(Pose.afterMove(blockedPose, direction, true))
        blockedPose = nextPose
        return blockedPose, Result.new(true, "MOVE_COMMITTED")
    end,
    turn = turn,
})
assert(not blockedReturn.ok and blockedReturn.code == "INVERSE_BLOCKED")
assert(failedMoves == 4, "a failed inverse edge must stop the composed return")

print("stair route checks passed")
