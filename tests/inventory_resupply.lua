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
        drop = function(amount)
            local stack = stacks[selected]
            if not stack then return false end
            stack.count = stack.count - (amount or stack.count)
            if stack.count == 0 then stacks[selected] = nil end
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
    assert(result.ok, tostring(result.code) .. ": " .. tostring(result.message))
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
    { name = "minecraft:coal", count = 1 },
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
    drop = function(amount)
        local stack = torchQuotaStacks[quotaSelected]
        if not stack then return false end
        stack.count = stack.count - (amount or stack.count)
        if stack.count == 0 then torchQuotaStacks[quotaSelected] = nil end
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

-- If a partial onboard coal stack needs only four more items, return the
-- other six from a pulled supply stack instead of keeping or burning them.
local partialStacks = {
    [1] = { name = "minecraft:coal", count = 60 },
}
local partialSupply = {
    { name = "minecraft:coal", count = 10 },
    { name = "minecraft:torch", count = 4 },
}
local partialSelected, returnedCoal = 1, 0
local partialApi = {
    getSelectedSlot = function() return partialSelected end,
    select = function(slot) partialSelected = slot return true end,
    getItemCount = function(slot) return partialStacks[slot] and partialStacks[slot].count or 0 end,
    getItemDetail = function(slot)
        return partialStacks[slot] and { name = partialStacks[slot].name }
    end,
    getFuelLevel = function() return 80 end,
    refuel = function(amount)
        return amount == 0 and partialStacks[partialSelected] ~= nil
            and partialStacks[partialSelected].name == "minecraft:coal"
    end,
    suck = function()
        local item = table.remove(partialSupply, 1)
        if not item then return false end
        partialStacks[partialSelected] = { name = item.name, count = item.count }
        return true
    end,
    drop = function(amount)
        local stack = partialStacks[partialSelected]
        if not stack then return false end
        local removed = amount or stack.count
        if stack.name == "minecraft:coal" then returnedCoal = returnedCoal + removed end
        stack.count = stack.count - removed
        if stack.count == 0 then partialStacks[partialSelected] = nil end
        return true
    end,
}
local partial = Resupply.run({
    turtle = partialApi,
    itemConfig = {
        fuel = { allowedItems = { "minecraft:coal" } },
        inventory = { fuelRetainedCount = 64, torchRetainedCount = 4 },
    },
    targetFuel = 80,
    torchTarget = 4,
    minimumTorches = 4,
})
assert(partial.ok, partial.code)
assert(returnedCoal == 6 and partialStacks[1].count == 60
    and partialStacks[2].count == 4 and partialStacks[2].name == "minecraft:coal"
    and partialStacks[3].count == 4 and partialStacks[3].name == "minecraft:torch"
    and partialSelected == 1,
    "resupply must return only coal above the aggregate quota and restore selection")

-- Searching for torches must not retain several coal stacks along the way.
local fourStacks = { [1] = { name = "minecraft:coal", count = 64 } }
local fourSupply = {}
for _ = 1, 4 do
    fourSupply[#fourSupply + 1] = { name = "minecraft:coal", count = 64 }
end
fourSupply[#fourSupply + 1] = { name = "minecraft:torch", count = 4 }
local fourSelected, fourReturned = 1, 0
local fourApi = {
    getSelectedSlot = function() return fourSelected end,
    select = function(slot) fourSelected = slot return true end,
    getItemCount = function(slot) return fourStacks[slot] and fourStacks[slot].count or 0 end,
    getItemDetail = function(slot)
        return fourStacks[slot] and { name = fourStacks[slot].name }
    end,
    getFuelLevel = function() return 80 end,
    refuel = function(amount) return amount == 0 end,
    suck = function()
        local item = table.remove(fourSupply, 1)
        if not item then return false end
        fourStacks[fourSelected] = { name = item.name, count = item.count }
        return true
    end,
    drop = function(amount)
        local stack = fourStacks[fourSelected]
        if not stack then return false end
        local removed = amount or stack.count
        if stack.name == "minecraft:coal" then fourReturned = fourReturned + removed end
        stack.count = stack.count - removed
        if stack.count == 0 then fourStacks[fourSelected] = nil end
        return true
    end,
}
local fourResult = Resupply.run({
    turtle = fourApi,
    itemConfig = {
        fuel = { allowedItems = { "minecraft:coal" } },
        inventory = { fuelRetainedCount = 64, torchRetainedCount = 4 },
    },
    targetFuel = 80,
    torchTarget = 4,
    minimumTorches = 4,
})
assert(fourResult.ok, fourResult.code)
local fourHeld = 0
for slot = 1, 16 do
    if fourStacks[slot] and fourStacks[slot].name == "minecraft:coal" then
        fourHeld = fourHeld + fourStacks[slot].count
    end
end
assert(fourHeld == 64 and fourReturned == 256 and fourSelected == 1,
    "four incidental coal stacks must go back to the supply chest")

print("inventory resupply checks passed")
