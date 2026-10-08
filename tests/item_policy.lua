local defaults = require("src.config.defaults")
local itemPolicy = require("src.config.item_policy")

local fuelItems = {
    "minecraft:coal",
    "minecraft:charcoal",
    "minecraft:coal_block",
}
for _, itemId in ipairs(fuelItems) do
    assert(itemPolicy.isFuel(itemId, defaults), itemId .. " should be fuel")
end
assert(not itemPolicy.isFuel("minecraft:diamond", defaults))

local pavingItems = {
    "minecraft:cobblestone",
    "minecraft:cobbled_deepslate",
    "minecraft:dirt",
    "minecraft:netherrack",
}
for _, itemId in ipairs(pavingItems) do
    assert(not itemPolicy.isPaving(itemId, defaults), itemId .. " should be disabled by default")
end
assert(not itemPolicy.isPaving("minecraft:coal", defaults))

local customConfig = {
    fuel = { allowedItems = { "example:solid_fuel" } },
    paving = { allowedItems = { "example:road_block" } },
}
assert(itemPolicy.isFuel("example:solid_fuel", customConfig))
assert(not itemPolicy.isPaving("example:road_block", customConfig))
assert(not itemPolicy.isFuel("minecraft:coal", customConfig))
assert(not itemPolicy.isPaving("minecraft:cobblestone", customConfig))
assert(not itemPolicy.isFuel("minecraft:coal", {}))
assert(not itemPolicy.isPaving("minecraft:cobblestone", {}))

local enabled = {
    fuel = { allowedItems = { "minecraft:coal" } },
    paving = { enabled = true, retainedCount = 1, allowedItems = { "minecraft:cobblestone" } },
    inventory = {
        fuelRetainedCount = 64,
        torchRetainedCount = 64,
        retainedItems = { ["minecraft:cobblestone"] = 9 },
    },
    ore = { names = { "minecraft:diamond_ore" }, valuableNames = {}, namePatterns = { "_ore$" } },
}
assert(itemPolicy.isPaving("minecraft:cobblestone", enabled))
assert(itemPolicy.retainedCount("minecraft:cobblestone", defaults) == 64,
    "mandatory backfill reserve applies while paving is disabled")
assert(itemPolicy.retainedCount("minecraft:cobblestone", enabled) == 9,
    "configured backfill reserve takes precedence over any paving quota")
assert(itemPolicy.mayConsumeForPaving("minecraft:cobblestone", enabled, 10))
assert(not itemPolicy.mayConsumeForPaving("minecraft:cobblestone", enabled, 9))
enabled.paving.enabled = false
assert(itemPolicy.retainedCount("minecraft:cobblestone", enabled) == 9,
    "configured reserve is independent of paving state")
enabled.paving.enabled = true
for _, protectedId in ipairs({ "minecraft:coal", "minecraft:torch", "minecraft:diamond_ore", "mod:unclassified" }) do
    enabled.paving.allowedItems[2] = protectedId
    enabled.paving.protectedItems = { "mod:unclassified" }
    assert(not itemPolicy.mayConsumeForPaving(protectedId, enabled, 80), protectedId .. " must be protected")
end

print("item policy tests passed")
