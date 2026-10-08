local InventoryService = require("src.inventory.service")
local defaults = require("src.config.defaults")

local count = 70
local selected = 6
local pose = { x = 0, y = 0, z = 0, facing = 0 }
local api = {
    getItemCount = function(slot) return slot == 2 and count or 0 end,
    getItemDetail = function(slot)
        if slot == 2 and count > 0 then return { name = "minecraft:cobblestone" } end
    end,
    getSelectedSlot = function() return selected end,
    select = function(slot) selected = slot return true end,
    drop = function(amount) count = count - (amount or count); return true end,
    inspect = function() return true, { name = "minecraft:chest" } end,
}
local config = {
    inventory = { pressureThreshold = 1 },
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
assert(service.serviceIfNeeded(), "accepted chest should complete the inventory service")
assert(count == 64, "configured cobblestone quota should remain after unload")
assert(selected == 6, "inventory service should restore the selected slot")
assert(pose.facing == 0, "inventory service should restore the saved facing")
defaults.paving.enabled = previousPaving

print("inventory service checks passed")
