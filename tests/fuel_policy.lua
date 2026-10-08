local FuelPolicy = require("src.fuel.policy")

local refuelTarget = nil
local tank = 10
local allowed, reason = FuelPolicy.canMove(10, 20, function(target)
    refuelTarget = target
    return false
end, function() return tank end)
assert(not allowed and reason == "INSUFFICIENT_FUEL")
assert(refuelTarget == 20, "policy should request the complete return-plus-reserve amount")

tank = 25
allowed, reason = FuelPolicy.canMove(10, 20, function(target)
    tank = target
    return true
end, function() return tank end)
assert(allowed and reason == "FUEL_SAFE")
assert(tank == 20, "successful onboard refuelling should reach the required threshold")

allowed, reason = FuelPolicy.canMove("unlimited", 1000)
assert(allowed and reason == "UNLIMITED_FUEL")

allowed, reason = FuelPolicy.canMove(30, 20, function() return true end, function() return 19 end)
assert(not allowed and reason == "INSUFFICIENT_FUEL", "movement must fail closed if the post-refuel tank is insufficient")

print("fuel policy checks passed")
