local Pose = require("src.navigation.pose")
local KnownRoute = require("src.fuel.known_route")

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

-- Existing explored edges can make the exact known return shorter.
local d = pose(0, 0, -2)
record(c, d)
local shortcut = KnownRoute.projectedReturnCost(route, d, a)
assert(shortcut == 1, "cost should use an already recorded route from the proposed pose")

-- Active excursion depth is represented by each successfully traversed edge.
local vein1, vein2 = pose(2, 0, -2), pose(2, 1, -2)
record(c, vein1)
record(vein1, vein2)
local veinCost = KnownRoute.projectedReturnCost(route, vein2, pose(2, 1, -3))
assert(veinCost == 6, "vein excursion depth must be included in the return cost")

local unknownCost, unknownReason = KnownRoute.projectedReturnCost(route, pose(20, 0, 20), pose(21, 0, 20))
assert(unknownCost == nil and unknownReason == "UNKNOWN_CURRENT_ROUTE", "unknown current route must fail closed")

print("known route fuel checks passed")
