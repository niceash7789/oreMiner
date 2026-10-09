-- Route-aware fuel admission for one proposed movement.
local Pose = require("src.navigation.pose")
local KnownRoute = require("src.fuel.known_route")
local FuelPolicy = require("src.fuel.policy")
local FuelLevel = require("src.fuel.level")

local RoutePolicy = {}

function RoutePolicy.canMove(options)
    if type(options) ~= "table"
        or type(options.pose) ~= "table"
        or type(options.route) ~= "table"
        or type(options.movement) ~= "string"
        or type(options.reserve) ~= "number"
        or type(options.getFuelLevel) ~= "function" then
        return false, "INVALID_ROUTE_FUEL_POLICY"
    end

    local proposed, poseResult = Pose.afterMove(options.pose, options.movement, true)
    if not poseResult.ok then return false, poseResult.code end

    local routeCost, routeReason = KnownRoute.projectedReturnCost(
        options.route, options.pose, proposed)
    if routeCost == nil then return false, routeReason end

    local requiredFuel = routeCost + options.reserve
    local allowed, reason = FuelPolicy.canMove(
        options.getFuelLevel(),
        requiredFuel,
        options.refuel,
        options.getFuelLevel)
    return allowed, reason, requiredFuel, proposed
end

-- Check an ore edge before its candidate block is dug. The subsequent
-- movement wrapper repeats admission, so this helper protects the block from
-- being removed when permitted onboard refuelling is needed or unavailable.
function RoutePolicy.canExplore(options)
    if type(options) ~= "table" or type(options.pose) ~= "table"
        or type(options.target) ~= "table" or type(options.route) ~= "table"
        or type(options.reserve) ~= "number"
        or type(options.getFuelLevel) ~= "function" then
        return false, "INVALID_ROUTE_FUEL_POLICY"
    end
    local level = options.getFuelLevel()
    if FuelLevel.isUnlimited(level) then return true, "UNLIMITED_FUEL" end
    if type(level) ~= "number" then return false, "INVALID_FUEL_LEVEL" end
    local cost, reason = KnownRoute.projectedReturnCost(
        options.route, options.pose, options.target)
    if cost == nil then return false, reason end
    local allowed, fuelReason = FuelPolicy.canMove(
        level, cost + options.reserve, options.refuel, options.getFuelLevel)
    return allowed, fuelReason, cost + options.reserve
end

return RoutePolicy
