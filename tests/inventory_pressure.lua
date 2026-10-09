local Pressure = require("src.inventory.pressure")
local defaults = require("src.config.defaults")

local counts = {}
local items = {}
local selected = 7
local turtleApi = {
    getItemCount = function(slot) return counts[slot] or 0 end,
    getItemDetail = function(slot) return items[slot] end,
    getSelectedSlot = function() return selected end,
    select = function(slot) selected = slot; return true end,
    transferTo = function(target)
        local source = selected
        local sourceItem = items[source]
        local targetItem = items[target]
        if not sourceItem or not targetItem
            or sourceItem.name ~= targetItem.name
            or sourceItem.nbt ~= targetItem.nbt then
            return false
        end
        local moved = math.min(counts[source], 64 - counts[target])
        counts[source] = counts[source] - moved
        counts[target] = counts[target] + moved
        if counts[source] == 0 then items[source] = nil end
        return moved > 0
    end,
}

assert(defaults.inventory.returnThreshold == 14)
counts[1] = 64
counts[2] = 7
counts[3] = 1
for slot = 4, 13 do counts[slot] = slot end
local occupiedCount, freeCount = Pressure.slotCounts(turtleApi)
assert(occupiedCount == 13 and freeCount == 3,
    "mixed full and partial stacks should count slots, not item quantities")
local reached, occupied = Pressure.reached(turtleApi, defaults.inventory.returnThreshold)
assert(not reached and occupied == 13, "13 occupied slots should leave work below threshold")

counts[14] = 1
reached, occupied = Pressure.reached(turtleApi, defaults.inventory.returnThreshold)
assert(reached and occupied == 14, "14 occupied slots should trigger pressure")

counts[1] = 0
reached, occupied = Pressure.reached(turtleApi, defaults.inventory.returnThreshold)
assert(not reached and occupied == 13, "emptying a slot should clear pressure")
occupiedCount, freeCount = Pressure.slotCounts(turtleApi)
assert(occupiedCount == 13 and freeCount == 3, "empty slots should be reflected in free count")

reached, occupied = Pressure.reached(turtleApi, 17)
assert(not reached and occupied.code == "INVALID_INVENTORY_THRESHOLD")

counts = { [1] = 40, [2] = 30, [3] = 20, [4] = 10 }
items = {
    [1] = { name = "minecraft:stone", nbt = "same" },
    [2] = { name = "minecraft:stone", nbt = "same" },
    [3] = { name = "minecraft:stone", nbt = "other" },
    [4] = { name = "minecraft:stone", nbt = "same" },
}
local consolidated = Pressure.consolidate(turtleApi)
assert(consolidated.ok and consolidated.transferred == 34,
    "compatible partial stacks should merge and report verified moved items")
assert(counts[1] == 64 and counts[2] == 16 and counts[3] == 20 and counts[4] == 0,
    "incompatible same-name stacks must remain separate")
assert(selected == 7, "consolidation should restore the selected slot")

print("inventory pressure checks passed")
