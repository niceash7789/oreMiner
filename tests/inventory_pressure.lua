local Pressure = require("src.inventory.pressure")
local defaults = require("src.config.defaults")

local counts = {}
local turtleApi = {
    getItemCount = function(slot) return counts[slot] or 0 end,
}

assert(defaults.inventory.pressureThreshold == 14)
for slot = 1, 13 do counts[slot] = 1 end
local reached, occupied = Pressure.reached(turtleApi, defaults.inventory.pressureThreshold)
assert(not reached and occupied == 13, "13 occupied slots should leave work below threshold")

counts[14] = 1
reached, occupied = Pressure.reached(turtleApi, defaults.inventory.pressureThreshold)
assert(reached and occupied == 14, "14 occupied slots should trigger pressure")

counts[1] = 0
reached, occupied = Pressure.reached(turtleApi, defaults.inventory.pressureThreshold)
assert(not reached and occupied == 13, "emptying a slot should clear pressure")

reached, occupied = Pressure.reached(turtleApi, 17)
assert(not reached and occupied.code == "INVALID_INVENTORY_THRESHOLD")

print("inventory pressure checks passed")
