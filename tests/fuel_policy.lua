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

local unlimitedCallbacks = 0
allowed, reason = FuelPolicy.canMove("unlimited", "not numeric", function()
    unlimitedCallbacks = unlimitedCallbacks + 1
    return false
end, function()
    unlimitedCallbacks = unlimitedCallbacks + 1
    return 0
end)
assert(allowed and reason == "UNLIMITED_FUEL")
assert(unlimitedCallbacks == 0, "unlimited fuel must bypass numeric checks and refuel callbacks")

allowed, reason = FuelPolicy.canMove(10, 20, function()
    return true
end, function()
    return "unlimited"
end)
assert(allowed and reason == "UNLIMITED_FUEL", "unlimited fuel reported after refuelling must bypass comparisons")

allowed, reason = FuelPolicy.canMove(30, 20, function() return true end, function() return 19 end)
assert(not allowed and reason == "INSUFFICIENT_FUEL", "movement must fail closed if the post-refuel tank is insufficient")

print("fuel policy checks passed")
