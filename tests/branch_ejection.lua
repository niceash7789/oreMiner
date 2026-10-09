local BranchEjection = require("src.inventory.branch_ejection")
local defaults = require("src.config.defaults")

local function fake(stacks, partial)
    local selected = 7
    local api = {
        getSelectedSlot = function() return selected end,
        select = function(slot) selected = slot return true end,
        getItemCount = function(slot) return stacks[slot] and stacks[slot].count or 0 end,
        getItemDetail = function(slot)
            local stack = stacks[slot]
            return stack and { name = stack.name } or nil
        end,
        transferTo = function() return false end,
        drop = function(amount)
            local stack = stacks[selected]
            if not stack then return false end
            local moved = partial and math.max(0, amount - 1) or amount
            stack.count = stack.count - moved
            return true
        end,
    }
    return api, function() return selected end
end

local stacks = {
    [2] = { name = "minecraft:cobblestone", count = 30 },
    [9] = { name = "mod:ore", count = 8 },
    [15] = { name = "minecraft:cobblestone", count = 50 },
}
local api, selected = fake(stacks, false)
local result = BranchEjection.run(api, defaults)
assert(result.ok and result.code == "EJECT_COMPLETE" and result.ejected == 16 and result.retained == 64)
assert(stacks[9].count == 8, "only cobblestone may be ejected")
assert(selected() == 7, "selected slot must be restored")

stacks = { [4] = { name = "minecraft:cobblestone", count = 70 } }
api = fake(stacks, true)
result = BranchEjection.run(api, defaults)
assert(not result.ok and result.code == "EJECT_FAILED" and result.cause == "CHEST_FULL")

stacks = { [1] = { name = "minecraft:cobblestone", count = 32 } }
api = fake(stacks, false)
result = BranchEjection.run(api, defaults)
assert(result.ok and result.code == "EJECT_NOT_NEEDED" and result.ejected == 0)

print("branch ejection checks passed")
