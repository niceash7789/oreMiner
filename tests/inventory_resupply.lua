local Resupply = require("src.inventory.resupply")

local apiCalls = 0
local noCallApi = setmetatable({}, { __index = function()
    return function() apiCalls = apiCalls + 1; return 0 end
end })
local validOptions = {
    turtle = noCallApi,
    itemConfig = { inventory = { fuelRetainedCount = 0 } },
    targetFuel = 10,
    torchTarget = 2,
    minimumTorches = 1,
}
for _, invalidOptions in ipairs({
    { targetFuel = 0 / 0 },
    { torchTarget = math.huge },
    { minimumTorches = 0.5 },
    { maxPulls = math.huge },
}) do
    local options = {}
    for key, value in pairs(validOptions) do options[key] = value end
    for key, value in pairs(invalidOptions) do options[key] = value end
    local result = Resupply.run(options)
    assert(not result.ok, "invalid resupply limits and quotas must be rejected")
end
local invalidQuota = {}
for key, value in pairs(validOptions) do invalidQuota[key] = value end
invalidQuota.itemConfig = { inventory = { fuelRetainedCount = -1 } }
assert(not Resupply.run(invalidQuota).ok, "invalid retained fuel quota must be rejected")
assert(apiCalls == 0, "invalid resupply options must be rejected before any turtle API call")

local function run(order, torchTarget, minimumTorches, shouldSucceed)
    local stacks = { [4] = { name = "minecraft:coal", count = 1 } }
    local supplies = {}
    for _, item in ipairs(order) do supplies[#supplies + 1] = item end
    local selected, fuel = 11, 80
    local api = {
        getSelectedSlot = function() return selected end,
        select = function(slot) selected = slot return true end,
        getItemCount = function(slot) return stacks[slot] and stacks[slot].count or 0 end,
        getItemDetail = function(slot) return stacks[slot] and { name = stacks[slot].name } end,
        getFuelLevel = function() return fuel end,
        refuel = function(amount)
            local stack = stacks[selected]
            if amount == 0 then return stack ~= nil and stack.name == "minecraft:coal" end
            if not stack or stack.name ~= "minecraft:coal" or stack.count == 0 then return false end
            stack.count = stack.count - 1
            fuel = fuel + 80
            return true
        end,
        suck = function()
            local nextItem = table.remove(supplies, 1)
            if not nextItem then return false end
            stacks[selected] = { name = nextItem.name, count = nextItem.count }
            return true
        end,
        drop = function()
            stacks[selected] = nil
            return true
        end,
    }
    local result = Resupply.run({
        turtle = api,
        itemConfig = {
            fuel = { allowedItems = { "minecraft:coal" } },
            inventory = { fuelRetainedCount = 2, torchRetainedCount = torchTarget or 4 },
        },
        targetFuel = 200,
        torchTarget = torchTarget or 4,
        minimumTorches = minimumTorches or 2,
        maxPulls = 6,
    })
    if shouldSucceed == false then
        assert(not result.ok, "expected resupply to refuse an insufficient departure quota")
        assert(selected == 11, "failed resupply must restore the selected slot")
        return result
    end
    assert(result.ok, result.code)
    assert(result.fuel >= 200 and result.torches >= (minimumTorches or 2))
    local onboardFuel = 0
    for slot = 1, 16 do
        if stacks[slot] and stacks[slot].name == "minecraft:coal" then
            onboardFuel = onboardFuel + stacks[slot].count
        end
    end
    assert(onboardFuel >= 2, "resupply must refill the physical emergency fuel quota")
    assert(selected == 11, "resupply must restore the selected slot")
    return result
end

run({
    { name = "minecraft:coal", count = 2 },
    { name = "minecraft:torch", count = 4 },
    { name = "minecraft:torch", count = 4 },
    { name = "minecraft:coal", count = 2 },
})
local partialTorchRestock = run({
    { name = "minecraft:coal", count = 2 },
    { name = "minecraft:torch", count = 4 },
    { name = "minecraft:coal", count = 2 },
}, 8, 4)
assert(partialTorchRestock.torches == 4,
    "meeting the minimum departure count must allow a partial configured torch target")
local insufficientTorchRestock = run({
    { name = "minecraft:coal", count = 2 },
    { name = "minecraft:torch", count = 1 },
}, 8, 2, false)
assert(not insufficientTorchRestock.ok and insufficientTorchRestock.code == "NO_TORCHES",
    "resupply must stop when available torches do not meet the departure minimum")
run({
    { name = "minecraft:torch", count = 4 },
    { name = "minecraft:coal", count = 2 },
    { name = "minecraft:coal", count = 2 },
})
-- Unexpected chest contents are returned and skipped; scanning continues
-- through later slots until both configured supply categories are found.
run({
    { name = "minecraft:dirt", count = 8 },
    { name = "minecraft:coal", count = 2 },
    { name = "minecraft:gravel", count = 5 },
    { name = "minecraft:torch", count = 4 },
    { name = "minecraft:coal", count = 2 },
})

local selected = 3
local emptySupply = {
    getSelectedSlot = function() return selected end,
    select = function(slot) selected = slot return true end,
    getItemCount = function() return 0 end,
    getItemDetail = function() return nil end,
    getFuelLevel = function() return 0 end,
    refuel = function() return false end,
    suck = function() return false end,
    drop = function() return false end,
}
local failed = Resupply.run({
    turtle = emptySupply,
    itemConfig = {
        fuel = { allowedItems = { "minecraft:coal" } },
        inventory = { fuelRetainedCount = 2 },
    },
    targetFuel = 200,
    torchTarget = 4,
    minimumTorches = 2,
    maxPulls = 2,
})
assert(not failed.ok and failed.code == "NO_FUEL_SUPPLY")
assert(selected == 3, "failed resupply must restore selected slot")

-- Extra torches encountered while searching for fuel must be returned, and
-- service must not exceed the configured one-stack retention quota.
local torchQuotaStacks = { [1] = { name = "minecraft:torch", count = 64 } }
local torchQuotaSupplies = {
    { name = "minecraft:torch", count = 64 },
    { name = "minecraft:cobblestone", count = 16 },
    { name = "minecraft:coal", count = 64 },
}
local quotaSelected, quotaFuel = 1, 0
local quotaApi = {
    getSelectedSlot = function() return quotaSelected end,
    select = function(slot) quotaSelected = slot return true end,
    getItemCount = function(slot) return torchQuotaStacks[slot] and torchQuotaStacks[slot].count or 0 end,
    getItemDetail = function(slot) return torchQuotaStacks[slot] and { name = torchQuotaStacks[slot].name } end,
    getFuelLevel = function() return quotaFuel end,
    refuel = function(amount)
        local stack = torchQuotaStacks[quotaSelected]
        if amount == 0 then return stack ~= nil and stack.name == "minecraft:coal" end
        if not stack or stack.name ~= "minecraft:coal" or stack.count <= 0 then return false end
        stack.count = stack.count - 1
        quotaFuel = quotaFuel + 80
        return true
    end,
    suck = function()
        local item = table.remove(torchQuotaSupplies, 1)
        if not item then return false end
        torchQuotaStacks[quotaSelected] = { name = item.name, count = item.count }
        return true
    end,
    drop = function()
        torchQuotaStacks[quotaSelected] = nil
        return true
    end,
}
local capped = Resupply.run({
    turtle = quotaApi,
    itemConfig = {
        fuel = { allowedItems = { "minecraft:coal" } },
        inventory = { fuelRetainedCount = 64, torchRetainedCount = 64 },
    },
    targetFuel = 80,
    torchTarget = 64,
    minimumTorches = 8,
})
assert(capped.ok, capped.code)
assert(capped.torches == 64, "resupply must cap onboard torches at one stack")
local cappedCoal = 0
for slot = 1, 16 do
    local stack = torchQuotaStacks[slot]
    if stack and stack.name == "minecraft:coal" then cappedCoal = cappedCoal + stack.count end
end
assert(cappedCoal == 64, "resupply must retain no more than one coal stack")

print("inventory resupply checks passed")
