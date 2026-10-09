local Paving = require("src.inventory.paving")
local SlotGuard = require("src.inventory.slot_guard")
local ItemPolicy = require("src.config.item_policy")

local function fixture(config)
    local selected, placements = 7, 0
    local items = {
        [1] = { name = "minecraft:coal", count = 8 },
        [2] = { name = "minecraft:torch", count = 8 },
        [3] = { name = "minecraft:diamond_ore", count = 1 },
        [4] = { name = "mod:mystery", count = 4 },
        [5] = { name = "minecraft:cobblestone", count = 4 },
    }
    local turtle = {
        detectDown = function() return false end,
        getSelectedSlot = function() return selected end,
        select = function(slot) selected = slot; return true end,
        getItemDetail = function(slot) return items[slot] end,
        getItemCount = function(slot) return items[slot] and items[slot].count or 0 end,
        placeDown = function()
            placements = placements + 1
            if items[selected] then items[selected].count = items[selected].count - 1 end
            return true
        end,
    }
    local result = Paving.tryDown(config, turtle, SlotGuard, ItemPolicy)
    return result, selected, placements
end

local config = {
    paving = {
        enabled = true,
        allowedItems = { "minecraft:coal", "minecraft:torch", "minecraft:diamond_ore", "mod:mystery", "minecraft:cobblestone" },
        protectedItems = { "mod:mystery" },
    },
    inventory = { retainedItems = { ["minecraft:cobblestone"] = 3 }, protectedItems = {} },
    fuel = { allowedItems = { "minecraft:coal" } },
    ore = { names = { "minecraft:diamond_ore" }, valuableNames = {}, ignoreNames = {}, namePatterns = { "_ore$" } },
}
local result, selected, placements = fixture({ paving = { enabled = false } })
assert(result.ok and result.code == "PAVING_DISABLED" and placements == 0 and selected == 7)

result, selected, placements = fixture(config)
assert(result.ok and result.placed and result.code == "PAVED")
assert(placements == 1 and selected == 7, "only excess allowed cobblestone is consumed and slot restored")

config.inventory.retainedItems["minecraft:cobblestone"] = 4
result, selected, placements = fixture(config)
assert(result.code == "PAVING_MATERIAL_UNAVAILABLE" and placements == 0,
    "stock at the reserve is not consumed")

config.paving.allowedItems = { "mod:mystery" }
result, selected, placements = fixture(config)
assert(result.code == "PAVING_MATERIAL_UNAVAILABLE" and placements == 0,
    "unknown material remains protected even when listed")

local badSelectPlaceCalls = 0
local failedApi = {
    detectDown = function() return false end,
    getSelectedSlot = function() return 16 end,
    select = function(slot)
        if slot == 16 then return true end
        return 2 -- a slot number is not literal success
    end,
    getItemDetail = function(slot)
        if slot == 5 then return { name = "minecraft:cobblestone" } end
        return nil
    end,
    getItemCount = function(slot) return slot == 5 and 100 or 0 end,
    placeDown = function() badSelectPlaceCalls = badSelectPlaceCalls + 1; return true end,
}
config.paving.allowedItems = { "minecraft:cobblestone" }
result = Paving.tryDown(config, failedApi, SlotGuard, ItemPolicy)
assert(not result.placed and badSelectPlaceCalls == 0,
    "a non-boolean select result must never reach placement")

print("inventory paving tests passed")
