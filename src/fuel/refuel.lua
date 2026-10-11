-- Consume configured onboard fuel with a finite call budget and observed progress.
local FuelLevel = require("src.fuel.level")
local FuelItemValidation = require("src.fuel.item_validation")
local ItemPolicy = require("src.config.item_policy")
local SlotGuard = require("src.inventory.slot_guard")

local Refuel = {}
local MAX_CONSUMED_ITEMS = 1024

local function validNumber(value)
    return type(value) == "number" and value == value
        and value >= 0 and value < math.huge
end

function Refuel.toTarget(api, target, config)
    if type(api) ~= "table" or not validNumber(target)
        or type(config) ~= "table" or type(config.fuel) ~= "table" then
        return false, "INVALID_REFUEL_OPTIONS"
    end
    for _, name in ipairs({ "getFuelLevel", "getItemCount", "getItemDetail",
        "getSelectedSlot", "select", "refuel" }) do
        if type(api[name]) ~= "function" then return false, "REFUEL_API_UNAVAILABLE" end
    end

    local level = api.getFuelLevel()
    if FuelLevel.isUnlimited(level) then return true, "UNLIMITED_FUEL" end
    if not validNumber(level) then return false, "INVALID_FUEL_LEVEL" end
    if level >= target then return true, "FUEL_READY" end

    local guarded = SlotGuard.run(api, function()
        local consumed = 0
        for slot = 1, 16 do
            if level >= target or consumed >= MAX_CONSUMED_ITEMS then break end
            local detail = api.getItemDetail(slot)
            if detail and ItemPolicy.isFuel(detail.name, config) then
                local usable = FuelItemValidation.verify(api, slot, config)
                if usable then
                    local count = api.getItemCount(slot)
                    if not validNumber(count) or count ~= math.floor(count) then
                        return { ok = false, code = "INVALID_FUEL_STACK" }
                    end
                    local limit = math.min(count, MAX_CONSUMED_ITEMS - consumed)
                    for _ = 1, limit do
                        if level >= target then break end
                        if api.refuel(1) ~= true then break end
                        local nextLevel = api.getFuelLevel()
                        local nextCount = api.getItemCount(slot)
                        consumed = consumed + 1
                        if not validNumber(nextCount) or nextCount ~= math.floor(nextCount)
                            or nextCount >= count then
                            return { ok = false, code = "REFUEL_NOT_VERIFIED" }
                        end
                        if FuelLevel.isUnlimited(nextLevel) then
                            return { ok = true, code = "UNLIMITED_FUEL" }
                        end
                        if not validNumber(nextLevel) or nextLevel <= level then
                            return { ok = false, code = "REFUEL_NOT_VERIFIED" }
                        end
                        level, count = nextLevel, nextCount
                    end
                end
            end
        end
        return { ok = level >= target, code = level >= target and "FUEL_READY" or "NO_FUEL" }
    end)
    if not guarded.ok then return false, guarded.code end
    return guarded.value.ok, guarded.value.code
end

return Refuel
