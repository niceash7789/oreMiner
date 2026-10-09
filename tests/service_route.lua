local RouteHome = require("src.navigation.route_home")
local KnownRoute = require("src.fuel.known_route")
local Pose = require("src.navigation.pose")
local Result = require("src.safety.result")

local origin = { x = 0, y = 0, z = 0, facing = 0 }
local route = assert(KnownRoute.new(origin))
local pose = { x = 0, y = 0, z = 0, facing = 0 }

local function commitMove(direction)
    local previous = pose
    local nextPose, outcome = Pose.afterMove(previous, direction, true)
    assert(outcome.ok)
    assert(KnownRoute.recordMove(route, previous, nextPose))
    pose = nextPose
end

-- Build the recorded route through surface entry, eight stair slices, the
-- landing, and a short main-shaft/junction/branch checkpoint.
for _ = 1, 4 do commitMove("forward") end
for _ = 1, 8 do
    commitMove("forward")
    commitMove("down")
end
commitMove("forward")
local landing = { x = pose.x, y = pose.y, z = pose.z, facing = pose.facing }
local turned = assert(Pose.afterTurn(pose, "right", true))
pose = turned
for _ = 1, 3 do commitMove("forward") end
local checkpoint = { x = pose.x, y = pose.y, z = pose.z, facing = pose.facing }

local function travel(target, homeFacing)
    local arrived, outcome = RouteHome.run({
        pose = pose,
        route = route,
        targetPose = target,
        homeFacing = homeFacing,
        move = function(direction)
            local nextPose, moveOutcome = Pose.afterMove(pose, direction, true)
            if not moveOutcome.ok then return pose, moveOutcome end
            assert(KnownRoute.hasEdge(route, pose, nextPose), "service must use a recorded clear edge")
            pose = nextPose
            return pose, Result.new(true, "MOVE_COMMITTED")
        end,
        turn = function(direction)
            local nextPose, turnOutcome = Pose.afterTurn(pose, direction, true)
            if not turnOutcome.ok then return pose, turnOutcome end
            pose = nextPose
            return pose, Result.new(true, "TURN_COMMITTED")
        end,
    })
    assert(outcome.ok, tostring(outcome.code))
    pose = arrived
end

travel(origin, origin.facing)
assert(pose.x == 0 and pose.y == 0 and pose.z == 0 and pose.facing == 0,
    "deep branch checkpoint must return to exact surface origin")
travel(checkpoint, checkpoint.facing)
assert(pose.x == checkpoint.x and pose.y == checkpoint.y and pose.z == checkpoint.z
    and pose.facing == checkpoint.facing,
    "service return must restore the saved checkpoint and facing")

-- If any required return edge is absent, travel must fail before taking an
-- unrecorded shortcut.
local blockedRoute = assert(KnownRoute.new(origin))
local blockedCalls = 0
local blockedPose, blocked = RouteHome.run({
    pose = checkpoint,
    route = blockedRoute,
    move = function() blockedCalls = blockedCalls + 1; return checkpoint, Result.new(true, "MOVE") end,
    turn = function() return checkpoint, Result.new(true, "TURN") end,
})
assert(blocked.code == "UNKNOWN_CURRENT_ROUTE" and blockedCalls == 0)
assert(blockedPose.x == checkpoint.x and blockedPose.y == checkpoint.y,
    "unknown return routes must fail without moving")

print("service route checks passed")
