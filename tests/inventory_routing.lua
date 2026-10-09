local InventoryService = require("src.inventory.service")
local defaults = require("src.config.defaults")

local function run(options)
    local stacks = {
        [1] = { name = "minecraft:coal", count = 12 },
        [2] = { name = "minecraft:cobblestone", count = 70 },
        [3] = { name = "minecraft:gravel", count = 9 },
        [4] = { name = "mod:valuable_ore", count = 3 },
        [5] = { name = "mod:unknown_drop", count = 2 },
    }
    local selected = 8
    local facing = 0
    local dropped = { [1] = {}, [2] = {}, [3] = {} }
    local chestByFacing = options.chests or { [1] = true, [2] = true, [3] = true }
    local acceptedByFacing = options.accepted or {}

    local api = {
        getSelectedSlot = function() return selected end,
        select = function(slot) selected = slot return true end,
        getItemCount = function(slot) return stacks[slot] and stacks[slot].count or 0 end,
        getItemDetail = function(slot)
            local stack = stacks[slot]
            return stack and { name = stack.name } or nil
        end,
        transferTo = function() return false end,
        inspect = function()
            if chestByFacing[facing] then
                return true, { name = acceptedByFacing[facing] or "minecraft:chest" }
            end
            return false
        end,
        drop = function(amount)
            local stack = stacks[selected]
            if not stack then return false end
            local moved = amount or stack.count
            if options.partialFacing == facing then moved = math.max(0, moved - 1) end
            stack.count = stack.count - moved
            dropped[facing][stack.name] = (dropped[facing][stack.name] or 0) + moved
            return true
        end,
    }
    local pose = { x = 0, y = 0, z = 0, facing = 0 }
    local config = {
        inventory = { returnThreshold = 1, autoConsolidate = false },
        base = {
            acceptedChestBlockIds = defaults.base.acceptedChestBlockIds,
            separateBulk = options.separateBulk,
        },
    }
    local itemConfig = {
        fuel = defaults.fuel,
        paving = defaults.paving,
        inventory = defaults.inventory,
        supplies = defaults.supplies,
        ore = defaults.ore,
    }
    local service = InventoryService.new({
        turtle = api,
        config = config,
        itemConfig = itemConfig,
        pose = function() return pose end,
        turnToFacing = function(target) facing = target; pose.facing = target; return true end,
        safeForward = function() return true end,
        up = function() return true end,
        down = function() return true end,
        report = function() end,
        reportError = function() end,
    })
    local ok, code = service.serviceIfNeeded()
    return ok, code, stacks, dropped, selected, facing
end

local ok, code, stacks, dropped, selected, facing = run({ separateBulk = true })
assert(ok and code == "SERVICE_COMPLETE")
assert(dropped[2]["minecraft:cobblestone"] == 6, "rear chest gets cobblestone above reserve")
assert(dropped[2]["minecraft:gravel"] == 9, "rear chest gets configured bulk")
assert(dropped[1]["mod:valuable_ore"] == 3 and dropped[1]["mod:unknown_drop"] == 2,
    "right chest gets ores and conservative unknown-item fallback")
assert(stacks[1].count == 12 and stacks[2].count == 64, "supply quotas remain onboard")
assert(selected == 8 and facing == 0, "service restores slot and canonical home facing")

ok, code, _, dropped = run({ separateBulk = false, chests = { [1] = true, [3] = true } })
assert(ok and code == "SERVICE_COMPLETE")
assert(dropped[1]["minecraft:cobblestone"] == 6 and dropped[1]["minecraft:gravel"] == 9,
    "without rear separation all carried excess routes right")

ok, code = run({ separateBulk = true, chests = { [1] = true, [3] = true } })
assert(not ok and code == "NO_BULK_CHEST")
ok, code = run({ separateBulk = false, chests = { [1] = true } })
assert(not ok and code == "NO_SUPPLY_CHEST")
ok, code = run({ separateBulk = false, chests = { [3] = true } })
assert(not ok and code == "NO_OUTPUT_CHEST")
ok, code = run({ separateBulk = false, partialFacing = 1 })
assert(not ok and code == "CHEST_FULL")

print("inventory routing checks passed")
