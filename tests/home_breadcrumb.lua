local KnownRoute = require("src.fuel.known_route")
local Motion = require("src.navigation.motion")
local RouteHome = require("src.navigation.route_home")
local State = require("src.persistence.state")
local FakeTurtle = require("tests.fake_turtle")
local Result = require("src.safety.result")

local origin = { x = 0, y = 0, z = 0, facing = 0 }
local route = assert(KnownRoute.new(origin))
local world = FakeTurtle.new(origin)
local pose = origin
local api = {
    forward = function() return world:move("forward", true) end,
    back = function() return world:move("back", true) end,
    up = function() return world:move("up", true) end,
    down = function() return world:move("down", true) end,
    turnLeft = function() return world:turn("left", true) end,
    turnRight = function() return world:turn("right", true) end,
}
local config = { branch_length = 30, num_branches = 20, spacing = 3,
    pave = false, vein_mine = true }
local state = assert(State.new(config, pose, route, "home-trail"))

local function advance(direction)
    local nextPose, outcome = Motion.move(pose, route, direction, api)
    assert(outcome.ok and nextPose)
    pose = nextPose
    state.pose, state.route = pose, route
    assert(State.validate(state), "each absolute pose and breadcrumb must be saveable")
end

local function face(direction)
    local nextPose, outcome = Motion.turn(pose, direction, api)
    assert(outcome.ok)
    pose = nextPose
    state.pose = pose
    assert(State.validate(state))
end

advance("forward")
face("right")
advance("forward")
face("left")
advance("forward")
face("left")
advance("forward")

local trail, trailCode = KnownRoute.trailHome(route, pose)
assert(trailCode == "ROUTE_TRAIL_COST" and #trail == 4)
assert(trail[1].x == 1 and trail[1].z == -2)
assert(trail[2].x == 1 and trail[2].z == -1)
assert(trail[3].x == 0 and trail[3].z == -1)
assert(trail[4].x == 0 and trail[4].z == 0)

-- A direct visit to an earlier committed cell removes the loop from the
-- pending home trail while retaining the cleared graph edge.
face("left")
advance("forward")
trail = assert(KnownRoute.trailHome(route, pose))
assert(#trail == 1 and trail[1].x == 0 and trail[1].z == 0)

-- A failed physical return keeps the last saved absolute position and step.
local failedPose = pose
local failedTrail = table.concat(route.trail, ";")
local stopped, failure = RouteHome.run({
    pose = pose, route = route, homeFacing = 0,
    turn = function(direction) face(direction) return pose, Result.new(true, "TURN") end,
    move = function()
        return pose, Result.new(false, "RETURN_BLOCKED")
    end,
})
assert(failure.code == "RETURN_BLOCKED" and stopped.x == failedPose.x
    and stopped.z == failedPose.z)
assert(table.concat(route.trail, ";") == failedTrail)

local arrived, outcome = RouteHome.run({
    pose = pose, route = route, homeFacing = 0,
    turn = function(direction) face(direction) return pose, Result.new(true, "TURN") end,
    move = function(direction) advance(direction) return pose, Result.new(true, "MOVE") end,
})
assert(outcome.ok and outcome.code == "HOME_REACHED")
assert(arrived.x == 0 and arrived.y == 0 and arrived.z == 0 and arrived.facing == 0)
assert(#route.trail == 1 and route.trail[1] == route.home)
assert(State.validate(state))

local broken = assert(State.new(config, origin, route, "bad-trail"))
broken.route.trail = { "0,0,0", "7,0,0" }
assert(not State.validate(broken), "a disconnected or stale breadcrumb is not loadable")

print("home breadcrumb checks passed")
