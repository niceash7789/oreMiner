local Chest = require("src.inventory.chest")
local defaults = require("src.config.defaults")

assert(Chest.acceptsBlock("minecraft:chest", defaults.base))
assert(Chest.acceptsBlock("minecraft:trapped_chest", defaults.base))
assert(not Chest.acceptsBlock("mod:crystal_chest", defaults.base))
assert(not Chest.acceptsBlock("mod:chest_like_block", defaults.base))
assert(not Chest.acceptsBlock("minecraft:chest", {}))

local function fakeTurtle(initialCount, apiResult, transferred)
    local count = initialCount
    local selected = nil
    local dropCalls = 0
    return {
        api = {
            select = function(slot) selected = slot return true end,
            getItemCount = function(slot) return slot == 3 and count or 0 end,
            drop = function(amount)
                dropCalls = dropCalls + 1
                count = math.max(0, count - math.min(transferred, amount or count))
                return apiResult
            end,
        },
        dropCalls = function() return dropCalls end,
    }
end

local full = fakeTurtle(12, true, 12)
local result = Chest.dropSlot(full.api, 3)
assert(result.ok and result.code == "DROP_COMPLETE" and result.transferred == 12)
assert(full.dropCalls() == 1)

local rejected = fakeTurtle(12, false, 0)
result = Chest.dropSlot(rejected.api, 3)
assert(not result.ok and result.code == "DROP_FAILED" and result.remaining == 12)

local partial = fakeTurtle(12, true, 5)
result = Chest.dropSlot(partial.api, 3)
assert(not result.ok and result.code == "CHEST_FULL" and result.remaining == 7)

local partialExact = fakeTurtle(12, true, 5)
result = Chest.dropSlotCount(partialExact.api, 3, 8)
assert(not result.ok and result.code == "CHEST_FULL" and result.remaining == 7)
assert(result.transferred == nil, "partial exact-count drop must not report completion")

local noTransfer = fakeTurtle(12, true, 0)
result = Chest.dropSlot(noTransfer.api, 3)
assert(not result.ok and result.code == "DROP_NOT_VERIFIED" and result.remaining == 12)

local falseAfterTransfer = fakeTurtle(12, false, 12)
result = Chest.dropSlot(falseAfterTransfer.api, 3)
assert(not result.ok and result.code == "DROP_FAILED" and result.remaining == 0)

local empty = fakeTurtle(0, true, 0)
result = Chest.dropSlot(empty.api, 3)
assert(result.ok and result.code == "DROP_EMPTY" and empty.dropCalls() == 0)

local function inventoryFake(stacks)
    local selected = nil
    local api = {
        select = function(slot) selected = slot return true end,
        getItemCount = function(slot) return stacks[slot] and stacks[slot].count or 0 end,
        getItemDetail = function(slot)
            return stacks[slot] and { name = stacks[slot].name } or nil
        end,
        drop = function(amount)
            local stack = stacks[selected]
            amount = amount or stack.count
            if amount > stack.count then return false end
            stack.count = stack.count - amount
            return true
        end,
    }
    return api
end

local retainedConfig = {
    fuel = { allowedItems = { "minecraft:coal" } },
    paving = {
        enabled = true,
        allowedItems = { "test:stone_a", "test:stone_b" },
        protectedItems = {},
    },
    inventory = {
        retainedItems = { ["test:stone_a"] = 5, ["test:stone_b"] = 3 },
        protectedItems = {},
    },
    ore = { names = {}, valuableNames = {}, ignoreNames = {}, namePatterns = { "_ore$" } },
}
local stacks = {
    [2] = { name = "test:stone_a", count = 4 },
    [7] = { name = "test:stone_a", count = 6 },
    [11] = { name = "test:stone_b", count = 2 },
    [15] = { name = "test:stone_b", count = 4 },
    [16] = { name = "minecraft:coal", count = 9 },
}
result = Chest.unload(inventoryFake(stacks), retainedConfig)
assert(result.ok, result.code)
assert(stacks[2].count == 4 and stacks[7].count == 1, "quota must span stacks and slots")
assert(stacks[11].count == 2 and stacks[15].count == 1, "each item ID gets its own configured quota")
assert(stacks[16].count == 9, "protected fuel must remain untouched")
assert(result.retained["test:stone_a"] == 5 and result.retained["test:stone_b"] == 3)

local partialUnloadStacks = {
    [4] = { name = "test:stone_a", count = 8 },
}
local partialUnloadApi = inventoryFake(partialUnloadStacks)
local originalDrop = partialUnloadApi.drop
partialUnloadApi.drop = function(amount)
    if amount == 3 then
        partialUnloadStacks[4].count = 7
        return true
    end
    return originalDrop(amount)
end
result = Chest.unload(partialUnloadApi, retainedConfig)
assert(not result.ok and result.code == "CHEST_FULL" and result.remaining == 7)
assert(partialUnloadStacks[4].count == 7, "partial unload must preserve and report the remainder")

local cobblestoneStacks = {
    [3] = { name = "minecraft:cobblestone", count = 4 },
    [12] = { name = "minecraft:cobblestone", count = 8 },
}
local cobblestoneConfig = {
    fuel = { allowedItems = { "minecraft:coal" } },
    paving = { enabled = false, allowedItems = { "minecraft:cobblestone" } },
    inventory = {
        retainedItems = { ["minecraft:cobblestone"] = 7 },
        protectedItems = {},
    },
    ore = { names = {}, valuableNames = {}, ignoreNames = {}, namePatterns = { "_ore$" } },
}
result = Chest.unload(inventoryFake(cobblestoneStacks), cobblestoneConfig)
assert(result.ok, result.code)
assert(cobblestoneStacks[3].count == 4 and cobblestoneStacks[12].count == 3,
    "unload must preserve the configured reserve across slots with paving disabled")
assert(result.retained["minecraft:cobblestone"] == 7)

print("chest policy tests passed")
