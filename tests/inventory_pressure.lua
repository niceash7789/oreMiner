local Pressure = require("src.inventory.pressure")
local defaults = require("src.config.defaults")

local counts = {}
local turtleApi = {
    getItemCount = function(slot) return counts[slot] or 0 end,
}

assert(defaults.inventory.pressureThreshold == 14)
counts[1] = 64
counts[2] = 7
counts[3] = 1
for slot = 4, 13 do counts[slot] = slot end
local occupiedCount, freeCount = Pressure.slotCounts(turtleApi)
assert(occupiedCount == 13 and freeCount == 3,
    "mixed full and partial stacks should count slots, not item quantities")
local reached, occupied = Pressure.reached(turtleApi, defaults.inventory.pressureThreshold)
assert(not reached and occupied == 13, "13 occupied slots should leave work below threshold")

counts[14] = 1
reached, occupied = Pressure.reached(turtleApi, defaults.inventory.pressureThreshold)
assert(reached and occupied == 14, "14 occupied slots should trigger pressure")

counts[1] = 0
reached, occupied = Pressure.reached(turtleApi, defaults.inventory.pressureThreshold)
assert(not reached and occupied == 13, "emptying a slot should clear pressure")
occupiedCount, freeCount = Pressure.slotCounts(turtleApi)
assert(occupiedCount == 13 and freeCount == 3, "empty slots should be reflected in free count")

reached, occupied = Pressure.reached(turtleApi, 17)
assert(not reached and occupied.code == "INVALID_INVENTORY_THRESHOLD")

print("inventory pressure checks passed")
