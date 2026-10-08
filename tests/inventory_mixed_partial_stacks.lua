local InventoryService = require("src.inventory.service")
local defaults = require("src.config.defaults")

local stacks = {
    [1] = { name = "test:stone", count = 3 },
    [4] = { name = "test:stone", count = 5 },
    [7] = { name = "minecraft:coal", count = 2 },
    [10] = { name = "test:ore", count = 4 },
    [13] = { name = "test:loose", count = 6 },
}
local selected = 9
local selectedSlot = nil
local api = {
    getItemCount = function(slot)
        return stacks[slot] and stacks[slot].count or 0
    end,
    getItemDetail = function(slot)
        local stack = stacks[slot]
        return stack and { name = stack.name } or nil
    end,
    getSelectedSlot = function() return selected end,
    select = function(slot)
        selected = slot
        selectedSlot = slot
        return true
    end,
    drop = function(amount)
        local stack = stacks[selectedSlot]
        if not stack or amount > stack.count then return false end
        stack.count = stack.count - amount
        return true
    end,
    inspect = function() return true, { name = "minecraft:chest" } end,
}

local itemConfig = {
    fuel = { allowedItems = { "minecraft:coal" } },
    paving = { enabled = true, allowedItems = { "test:stone", "test:loose" } },
    inventory = {
        retainedItems = { ["test:stone"] = 6 },
        protectedItems = {},
    },
    ore = { names = {}, valuableNames = {}, ignoreNames = {}, namePatterns = {} },
}
local config = {
    inventory = { pressureThreshold = 1 },
    base = defaults.base,
}
local pose = { x = 0, y = 0, z = 0, facing = 0 }
local service = InventoryService.new({
    turtle = api,
    config = config,
    itemConfig = itemConfig,
    pose = function() return pose end,
    turnToFacing = function(facing) pose.facing = facing; return true end,
    safeForward = function() return true end,
    up = function() return true end,
    down = function() return true end,
    report = function() end,
    reportError = function(message) error(message) end,
})

local serviced, code = service.serviceIfNeeded()
assert(serviced and code == "SERVICE_COMPLETE")
assert(stacks[1].count == 3 and stacks[4].count == 3,
    "aggregate quota must retain six items across mixed partial stacks: "
        .. tostring(stacks[1].count) .. "/" .. tostring(stacks[4].count))
assert(stacks[7].count == 2, "coal fuel must remain untouched")
assert(stacks[10].count == 4, "ore must remain untouched")
assert(stacks[13] == nil or stacks[13].count == 0, "unprotected material without a quota must unload")
assert(selected == 9, "service must restore the selected slot")
assert(pose.x == 0 and pose.y == 0 and pose.z == 0 and pose.facing == 0,
    "base service must leave the turtle at its original pose")

print("mixed partial stack inventory service test passed")
