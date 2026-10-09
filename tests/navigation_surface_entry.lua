local KnownRoute = require("src.fuel.known_route")
local Motion = require("src.navigation.motion")
local Pose = require("src.navigation.pose")
local SurfaceEntry = require("src.navigation.surface_entry")
local FakeTurtle = require("tests.fake_turtle")

local function copyPose(pose)
    return { x = pose.x, y = pose.y, z = pose.z, facing = pose.facing }
end

local function assertPose(actual, expected, message)
    assert(actual and actual.x == expected.x and actual.y == expected.y
        and actual.z == expected.z and actual.facing == expected.facing, message)
end

local function harness(startPose, outcomes)
    local world = FakeTurtle.new(startPose, outcomes)
    local route = assert(KnownRoute.new(startPose))
    local pose = copyPose(startPose)
    local api = {
        forward = function() return world:move("forward") end,
        back = function() return world:move("back") end,
    }
    return {
        move = function(movement)
            local updated, outcome = Motion.move(pose, route, movement, api)
            if outcome.ok then pose = updated end
            return updated, outcome
        end,
        pose = function() return copyPose(pose) end,
        route = route,
        world = world,
    }
end

local expectedMouths = {
    [0] = { x = 0, y = 0, z = -4, facing = 0 },
    [1] = { x = 4, y = 0, z = 0, facing = 1 },
    [2] = { x = 0, y = 0, z = 4, facing = 2 },
    [3] = { x = -4, y = 0, z = 0, facing = 3 },
}

for facing = 0, 3 do
    local origin = { x = 0, y = 0, z = 0, facing = facing }
    local run = harness(origin, {
        forward = { true, true, true, true },
        back = { true, true, true, true },
    })
    local mouth, entered = SurfaceEntry.enter({ pose = origin, move = run.move })
    assert(entered.ok and entered.code == "SURFACE_ENTRY_COMPLETE" and entered.completed == 4)
    assertPose(mouth, expectedMouths[facing], "entry mouth must be exactly four level blocks away")
    assertPose(run.pose(), mouth, "entry pose must match the simulated world")
    local firstStep = assert(Pose.afterMove(origin, "forward", true))
    assert(KnownRoute.hasEdge(run.route, origin, firstStep),
        "entry movement must use the route-recording motion boundary")

    local restored, returned = SurfaceEntry.returnToOrigin({
        pose = mouth,
        origin = origin,
        move = run.move,
    })
    assert(returned.ok and returned.code == "SURFACE_ORIGIN_RESTORED"
        and returned.completed == 4)
    assertPose(restored, origin, "four checked back moves must restore the exact origin")
    assertPose(run.pose(), origin, "return pose must match the simulated world")
    assert(run.world:callCount("forward") == 4 and run.world:callCount("back") == 4,
        "surface route must contain exactly four moves in each direction")
end

local origin = { x = 0, y = 0, z = 0, facing = 0 }
local failedEntry = harness(origin, { forward = { true, true, false, true } })
local stopped, failure = SurfaceEntry.enter({ pose = origin, move = failedEntry.move })
assert(not failure.ok and failure.code == "MOVE_FAILED" and failure.completed == 2)
assertPose(stopped, { x = 0, y = 0, z = -2, facing = 0 },
    "failed entry must retain only successfully committed movement")
assert(failedEntry.world:callCount("forward") == 3,
    "entry must not make another blind move after failure")

local fullEntry = harness(origin, {
    forward = { true, true, true, true },
    back = { true, false, true },
})
local mouth = assert(SurfaceEntry.enter({ pose = origin, move = fullEntry.move }))
local partialReturn, returnFailure = SurfaceEntry.returnToOrigin({
    pose = mouth,
    origin = origin,
    move = fullEntry.move,
})
assert(not returnFailure.ok and returnFailure.code == "MOVE_FAILED" and returnFailure.completed == 1)
assertPose(partialReturn, { x = 0, y = 0, z = -3, facing = 0 },
    "failed return must preserve the last committed known-route pose")
assert(fullEntry.world:callCount("back") == 2,
    "return must stop immediately after a failed known-route move")

local rejectedPose, rejected = SurfaceEntry.returnToOrigin({
    pose = { x = 1, y = 0, z = -4, facing = 0 },
    origin = origin,
    move = function() error("invalid start must not move") end,
})
assert(not rejected.ok and rejected.code == "POSITION_ERROR")
assertPose(rejectedPose, { x = 1, y = 0, z = -4, facing = 0 },
    "invalid return start must remain unchanged")

print("navigation surface entry checks passed")
