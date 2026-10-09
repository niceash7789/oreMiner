local InventoryService = require("src.inventory.service")
local Pressure = require("src.inventory.pressure")
local defaults = require("src.config.defaults")

local count = 70
local selected = 6
local consolidationCalls = 0
local originalConsolidate = Pressure.consolidate
local originalReached = Pressure.reached
Pressure.consolidate = function(...)
    consolidationCalls = consolidationCalls + 1
    return originalConsolidate(...)
end
Pressure.reached = function(...)
    assert(consolidationCalls > 0, "pressure must be measured after consolidation")
    return originalReached(...)
end
local pose = { x = 0, y = 0, z = 0, facing = 0 }
local api = {
    getItemCount = function(slot) return slot == 2 and count or 0 end,
    getItemDetail = function(slot)
        if slot == 2 and count > 0 then return { name = "minecraft:cobblestone" } end
    end,
    getSelectedSlot = function() return selected end,
    select = function(slot) selected = slot return true end,
    transferTo = function() return false end,
    drop = function(amount) count = count - (amount or count); return true end,
    inspect = function() return true, { name = "minecraft:chest" } end,
}
local config = {
    inventory = { returnThreshold = 1 },
    base = defaults.base,
}
local previousPaving = defaults.paving.enabled
defaults.paving.enabled = true
local service = InventoryService.new({
    turtle = api,
    config = config,
    itemConfig = defaults,
    pose = function() return pose end,
    turnToFacing = function(facing) pose.facing = facing; return true end,
    safeForward = function() return true end,
    up = function() return true end,
    down = function() return true end,
    report = function() end,
    reportError = function(message) error(message) end,
})

assert(service.pressureReached(), "occupied-slot threshold should be evaluated by the service")
assert(consolidationCalls > 0, "pressure should consolidate before measuring occupied slots")
local serviced, serviceCode = service.serviceIfNeeded()
assert(serviced and serviceCode == "SERVICE_COMPLETE", "accepted chest should report completed service")
assert(count == 64, "configured cobblestone quota should remain after unload")
assert(selected == 6, "inventory service should restore the selected slot")
assert(pose.facing == 0, "inventory service should restore the saved facing")

pose.x = 1
count = 70
local forwardCalls = 0
local failedFacingService = InventoryService.new({
    turtle = api,
    config = config,
    itemConfig = defaults,
    pose = function() return pose end,
    turnToFacing = function() return false end,
    safeForward = function() forwardCalls = forwardCalls + 1; return true end,
    up = function() return true end,
    down = function() return true end,
    report = function() end,
    reportError = function() end,
})
local failedService = failedFacingService.serviceIfNeeded()
assert(failedService == false, "service should stop when checked facing fails")
assert(forwardCalls == 0, "service must not move after a failed facing change")
defaults.paving.enabled = previousPaving
Pressure.consolidate = originalConsolidate
Pressure.reached = originalReached

print("inventory service checks passed")
