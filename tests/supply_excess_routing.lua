local Service = require("src.inventory.service")
local defaults = require("src.config.defaults")

local function run(supplyAccepts)
    local stacks = {
        { name = "minecraft:coal", count = 50 },
        { name = "minecraft:coal", count = 30 },
        { name = "minecraft:torch", count = 70 },
        { name = "minecraft:iron_ore", count = 12 },
    }
    local pose = { x = 0, y = 0, z = 0, facing = 0 }
    local selected = 5
    local drops = {}
    local api = {
        getSelectedSlot = function() return selected end,
        select = function(slot) selected = slot; return true end,
        getItemCount = function(slot) return stacks[slot] and stacks[slot].count or 0 end,
        getItemDetail = function(slot)
            local stack = stacks[slot]
            return stack and stack.count > 0 and { name = stack.name } or nil
        end,
        inspect = function() return true, { name = "minecraft:chest" } end,
        drop = function(amount)
            local stack = stacks[selected]
            if pose.facing == 3 and not supplyAccepts then return false end
            drops[#drops + 1] = { facing = pose.facing, name = stack.name, count = amount }
            stack.count = stack.count - amount
            return true
        end,
    }
    local service = Service.new({
        turtle = api,
        config = { inventory = { returnThreshold = 1, autoConsolidate = false }, base = defaults.base },
        itemConfig = defaults,
        pose = function() return pose end,
        route = function() return {} end,
        turnToFacing = function(facing) pose.facing = facing; return true end,
        travel = function(target)
            pose.x, pose.y, pose.z, pose.facing = target.x, target.y, target.z, target.facing
            return true
        end,
        report = function() end,
        reportError = function() end,
    })
    local ok, code = service.serviceIfNeeded(true)
    assert(selected == 5 and pose.facing == 0,
        "slot=" .. tostring(selected) .. " facing=" .. tostring(pose.facing)
            .. " code=" .. tostring(code))
    return ok, code, drops, stacks
end

local ok, code, drops, stacks = run(true)
assert(ok and code == "SERVICE_COMPLETE")
assert(#drops == 3, "unexpected drops: " .. #drops .. " code=" .. tostring(code))
assert(drops[1].facing == 3 and drops[1].name == "minecraft:coal" and drops[1].count == 16)
assert(drops[2].facing == 3 and drops[2].name == "minecraft:torch" and drops[2].count == 6)
assert(drops[3].facing == 1 and drops[3].name == "minecraft:iron_ore" and drops[3].count == 12)
assert(stacks[1].count + stacks[2].count == 64 and stacks[3].count == 64)

ok, code, drops = run(false)
assert(not ok and code == "UNLOAD_FAILED" and #drops == 0,
    "a failed supply return must stop before output routing")

print("supply excess routing checks passed")
