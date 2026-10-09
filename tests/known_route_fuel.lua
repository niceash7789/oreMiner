local Pose = require("src.navigation.pose")
local KnownRoute = require("src.fuel.known_route")
local RoutePolicy = require("src.fuel.route_policy")

local home = assert(Pose.new(0, 0, 0, 0))
local route = assert(KnownRoute.new(home))
local function pose(x, y, z)
    return { x = x, y = y, z = z, facing = 0 }
end
local function record(fromPose, toPose)
    assert(KnownRoute.recordMove(route, fromPose, toPose))
end

-- A winding cleared route costs its actual edge count, not Manhattan distance.
local a, b, c = pose(0, 0, -1), pose(1, 0, -1), pose(1, 0, -2)
record(home, a)
record(a, b)
record(b, c)
local cost, reason = KnownRoute.projectedReturnCost(route, c, pose(1, 0, -3))
assert(cost == 4 and reason == "KNOWN_ROUTE_COST", "new outward edge must include the full retrace")
local phaseState = { pose = c, route = route, progress = { phase = "stairs" } }
local homeCost, homeReason = KnownRoute.costHome(phaseState)
assert(homeCost == 3 and homeReason == "KNOWN_ROUTE_COST",
    "phase-independent home estimate must count the exact recorded route edges")

local uncertainCost, uncertainReason = KnownRoute.costHome({
    pose = c, route = route, poseCertainty = "uncertain",
})
assert(uncertainCost == nil and uncertainReason == "POSITION_UNCERTAIN",
    "an uncertain pose must not produce an actionable route-home cost")
local pendingCost, pendingReason = KnownRoute.costHome({
    pose = c, route = route, poseCertainty = "known",
    pendingAction = { kind = "move", direction = "forward" },
})
assert(pendingCost == nil and pendingReason == "POSITION_UNCERTAIN",
    "a durable uncommitted action must not produce a route-home cost")

-- Existing explored edges can make the exact known return shorter.
local d = pose(0, 0, -2)
record(c, d)
local shortcut = KnownRoute.projectedReturnCost(route, d, a)
assert(shortcut == 1, "cost should use an already recorded route from the proposed pose")

-- Active excursion depth is represented by each successfully traversed edge.
local vein1, vein2 = pose(2, 0, -2), pose(2, 1, -2)
record(c, vein1)
record(vein1, vein2)
record(vein2, pose(2, 1, -3))
local veinCost = KnownRoute.projectedReturnCost(route, vein2, pose(2, 1, -3))
assert(veinCost == 6, "vein excursion depth must be included in the return cost")
local veinHome = pose(0, 0, 0)
local veinRoute = assert(KnownRoute.new(veinHome))
local checkpoint = pose(1, 0, 0)
local horizontal = pose(1, 0, -1)
local vertical = pose(1, 1, -1)
local activePose = pose(1, 1, -2)
record = function(fromPose, toPose) assert(KnownRoute.recordMove(veinRoute, fromPose, toPose)) end
record(veinHome, checkpoint)
record(checkpoint, horizontal)
record(horizontal, vertical)
record(vertical, activePose)
local veinState = {
    pose = activePose, route = veinRoute,
    vein = {
        stage = "active", checkpoint = checkpoint,
        visited = { ["1,1,-1"] = true, ["1,0,-1"] = true },
        route = {
            { inverse = "back", facing = 0 },
            { inverse = "down", facing = 0 },
            { inverse = "back", facing = 0 },
        },
    },
}
local veinHomeCost = assert(KnownRoute.costHome(veinState))
assert(veinHomeCost == 4,
    "home estimate must validate and account for saved vein breadcrumb depth")
local badVeinState = {
    pose = activePose, route = veinRoute,
    vein = { stage = "entering", checkpoint = checkpoint, visited = {}, route = {} },
}
local badCost, badReason = KnownRoute.costHome(badVeinState)
assert(badCost == nil and badReason == "UNKNOWN_VEIN_RETURN_ROUTE",
    "invalid vein breadcrumbs must fail closed instead of using a guessed route")

-- Ore discovery admission must use the full known return route plus reserve
-- and may safely consume permitted onboard fuel before digging the candidate.
local fuelLevel = 3
local requestedFuel
local allowed, exploreReason, requiredFuel = RoutePolicy.canExplore({
    pose = vein2, target = pose(2, 1, -3), route = route, reserve = 100,
    getFuelLevel = function() return fuelLevel end,
    refuel = function(target)
        requestedFuel = target
        fuelLevel = target
        return true
    end,
})
assert(allowed and exploreReason == "FUEL_SAFE" and requiredFuel == 106)
assert(requestedFuel == 106 and fuelLevel == 106,
    "vein discovery should refuel to the exact known-route commitment")

fuelLevel = 3
allowed, exploreReason = RoutePolicy.canExplore({
    pose = vein2, target = pose(2, 1, -3), route = route, reserve = 100,
    getFuelLevel = function() return fuelLevel end,
    refuel = function() return false end,
})
assert(not allowed and exploreReason == "INSUFFICIENT_FUEL",
    "failed vein refuelling must deny ore discovery")

allowed, exploreReason = RoutePolicy.canExplore({
    pose = vein2, target = pose(2, 1, -3), route = route, reserve = 100,
    getFuelLevel = function() return "unlimited" end,
})
assert(allowed and exploreReason == "UNLIMITED_FUEL",
    "unlimited fuel should retain the same safe admission path")

local unknownCost, unknownReason = KnownRoute.projectedReturnCost(route, pose(20, 0, 20), pose(21, 0, 20))
assert(unknownCost == nil and unknownReason == "UNKNOWN_CURRENT_ROUTE", "unknown current route must fail closed")

print("known route fuel checks passed")
