local StairRoute = require("src.navigation.stair_route")
local Landing = require("src.navigation.floor_landing")
local Pose = require("src.navigation.pose")
local Result = require("src.safety.result")

local pose = { x = 0, y = 0, z = 0, facing = 0 }
local turns = 0
local moves = 0
local savedSteps = 0
local savedRoute

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
    saveProgress = function(progress)
        assert(progress.floor == 1 and progress.stairStep == savedSteps + 1)
        savedSteps = savedSteps + 1
        return true, Result.new(true, "PROGRESS_SAVED")
    end,
    prepareLanding = function(rear)
        assert(rear.x == 0 and rear.y == -8 and rear.z == -12 and rear.facing == 0)
        return Landing.prepare({ pose = rear, move = move, turn = turn, clear = clear })
    end,
    saveLanding = function(route)
        savedRoute = route
        return true, Result.new(true, "LANDING_SAVED")
    end,
})

assert(outcome.ok and outcome.code == "LANDING_RECORDED")
assert(landingPose.x == 0 and landingPose.y == -8 and landingPose.z == -13)
assert(savedSteps == 8 and savedRoute.floor == 1)
assert(savedRoute.origin.z == 0 and savedRoute.mouth.z == -4)
assert(savedRoute.rear.z == -12 and savedRoute.landing.z == -13)
assert(turns > 0 and moves > 0)

local returned, returnOutcome = StairRoute.returnToSurface({
    pose = landingPose,
    route = savedRoute,
    move = move,
    turn = turn,
})
assert(returnOutcome.ok and returnOutcome.code == "SURFACE_ORIGIN_RESTORED")
assert(returned.x == 0 and returned.y == 0 and returned.z == 0 and returned.facing == 0)
assert(pose.x == 0 and pose.y == 0 and pose.z == 0 and pose.facing == 0)

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

print("stair route checks passed")
