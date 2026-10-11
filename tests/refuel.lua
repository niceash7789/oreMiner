local Refuel = require("src.fuel.refuel")

local config = { fuel = { allowedItems = { "minecraft:coal" } } }
local selected, fuel, count, calls = 7, 0, 3, 0
local api = {
    getFuelLevel = function() return fuel end,
    getItemCount = function(slot) return slot == 2 and count or 0 end,
    getItemDetail = function(slot)
        if slot == 2 and count > 0 then return { name = "minecraft:coal" } end
    end,
    getSelectedSlot = function() return selected end,
    select = function(slot) selected = slot; return true end,
    refuel = function(amount)
        if amount == 0 then return selected == 2 and count > 0 end
        calls = calls + 1
        if selected ~= 2 or count == 0 then return false end
        count = count - 1
        fuel = fuel + 80
        return true
    end,
}

local ready, code = Refuel.toTarget(api, 100, config)
assert(ready and code == "FUEL_READY" and fuel == 160 and count == 1
    and calls == 2 and selected == 7,
    "configured fuel must reach the target with observed item/fuel progress")

fuel, count, calls = 0, 1, 0
api.refuel = function(amount)
    if amount == 0 then return true end
    calls = calls + 1
    return true
end
ready, code = Refuel.toTarget(api, 80, config)
assert(not ready and code == "REFUEL_NOT_VERIFIED" and calls == 1 and selected == 7,
    "a lying refuel API must not make an unbounded loop or admit movement")

fuel, count, calls = 0, 2000, 0
api.refuel = function(amount)
    if amount == 0 then return true end
    calls = calls + 1
    count = count - 1
    fuel = fuel + 1
    return true
end
ready, code = Refuel.toTarget(api, 2000, config)
assert(not ready and code == "NO_FUEL" and calls == 1024 and selected == 7,
    "modded stack sizes must still obey the physical refuel call budget")

fuel, calls = "unlimited", 0
ready, code = Refuel.toTarget(api, 2000, config)
assert(ready and code == "UNLIMITED_FUEL" and calls == 0)

local invalidCalls = 0
local noCallApi = setmetatable({}, { __index = function()
    return function() invalidCalls = invalidCalls + 1 end
end })
ready, code = Refuel.toTarget(noCallApi, math.huge, config)
assert(not ready and code == "INVALID_REFUEL_OPTIONS" and invalidCalls == 0,
    "invalid targets must stop before turtle access")

print("bounded refuel checks passed")
