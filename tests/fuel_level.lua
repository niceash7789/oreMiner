local FuelLevel = require("src.fuel.level")

assert(FuelLevel.isUnlimited("unlimited"))
assert(not FuelLevel.isUnlimited(0))
assert(FuelLevel.format("unlimited") == "unlimited")
assert(FuelLevel.format(12) == "12")
assert(FuelLevel.format(nil) == "unavailable")
assert(FuelLevel.consumed(20, 19) == 1)
assert(FuelLevel.consumed(20, 20) == 0)
assert(FuelLevel.consumed(20, 21) == 0, "fuel increases are not consumption")
assert(FuelLevel.consumed("unlimited", "unlimited") == 0)
assert(FuelLevel.consumed(20, "unlimited") == 0)

local FuelPolicy = require("src.fuel.policy")
local admitted, reason = FuelPolicy.canMove("unlimited", 100)
assert(admitted and reason == "UNLIMITED_FUEL")

print("fuel level checks passed")
