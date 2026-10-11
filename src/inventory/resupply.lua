-- Bounded fuel and torch extraction from the configured supply chest.
local ItemPolicy = require("src.config.item_policy")
local SlotGuard = require("src.inventory.slot_guard")
local FuelLevel = require("src.fuel.level")

local Resupply = {}

local function isNonNegativeInteger(value)
    return type(value) == "number" and value >= 0
        and value == value and value < math.huge and value == math.floor(value)
end

local function validateOptions(options)
    if type(options) ~= "table" or type(options.turtle) ~= "table"
        or type(options.itemConfig) ~= "table"
        or not isNonNegativeInteger(options.targetFuel)
        or not isNonNegativeInteger(options.torchTarget)
        or not isNonNegativeInteger(options.minimumTorches) then
        return false, "INVALID_RESUPPLY_OPTIONS"
    end
    local maxPulls = options.maxPulls or 32
    if not isNonNegativeInteger(maxPulls) or maxPulls < 1 then
        return false, "INVALID_RESUPPLY_LIMIT"
    end
    local inventory = options.itemConfig.inventory
    local fuelQuota = type(inventory) == "table" and inventory.fuelRetainedCount or 0
    local torchQuota = type(inventory) == "table" and inventory.torchRetainedCount or 0
    if not isNonNegativeInteger(fuelQuota) then
        return false, "INVALID_RESUPPLY_OPTIONS"
    end
    if not isNonNegativeInteger(torchQuota) then
        return false, "INVALID_RESUPPLY_OPTIONS"
    end
    for _, name in ipairs({ "getSelectedSlot", "getItemCount", "getItemDetail", "getFuelLevel", "select", "refuel", "suck", "drop" }) do
        if type(options.turtle[name]) ~= "function" then
            return false, "RESUPPLY_API_UNAVAILABLE"
        end
    end
    return true
end

local function inventoryCount(api, itemId)
    local total = 0
    for slot = 1, 16 do
        local count = api.getItemCount(slot)
        if type(count) ~= "number" or count < 0 then return nil end
        if count > 0 then
            local detail = api.getItemDetail(slot)
            if detail and detail.name == itemId then total = total + count end
        end
    end
    return total
end

local function inventoryFuelCount(api, config)
    local total = 0
    for slot = 1, 16 do
        local count = api.getItemCount(slot)
        if type(count) ~= "number" or count < 0 then return nil end
        if count > 0 then
            local detail = api.getItemDetail(slot)
            if detail and ItemPolicy.isFuel(detail.name, config) then
                total = total + count
            end
        end
    end
    return total
end

local function refuelTo(api, config, target)
    local fuel = api.getFuelLevel()
    if FuelLevel.isUnlimited(fuel) then return true end
    if type(fuel) ~= "number" then return false, "INVALID_FUEL_LEVEL" end

    local guarded = SlotGuard.run(api, function()
        for slot = 1, 16 do
            if fuel >= target then break end
            local detail = api.getItemDetail(slot)
            if detail and ItemPolicy.isFuel(detail.name, config) then
                if api.select(slot) ~= true or api.refuel(0) ~= true then
                    return false, "NO_FUEL_SUPPLY"
                end
                local count = api.getItemCount(slot)
                if type(count) ~= "number" or count < 0 then
                    return false, "SUPPLY_COUNT_UNAVAILABLE"
                end
                while fuel < target and count > 0 do
                    local before = fuel
                    local beforeCount = count
                    if api.refuel(1) ~= true then break end
                    fuel = api.getFuelLevel()
                    count = api.getItemCount(slot)
                    if type(fuel) ~= "number" or type(count) ~= "number" or count < 0 then
                        return false, "INVALID_FUEL_LEVEL"
                    end
                    if fuel <= before or count >= beforeCount then
                        return false, "REFUEL_NOT_VERIFIED"
                    end
                end
            end
        end
        local level = api.getFuelLevel()
        return FuelLevel.isUnlimited(level) or (type(level) == "number" and level >= target),
            "NO_FUEL_SUPPLY"
    end)
    if not guarded.ok then return false, guarded.code end
    return guarded.value
end

local function firstEmptySlot(api)
    for slot = 1, 16 do
        local count = api.getItemCount(slot)
        if type(count) ~= "number" or count < 0 then return nil end
        if count == 0 then return slot end
    end
    return nil
end

local function dropCurrentSlot(api)
    local slot = api.getSelectedSlot()
    local before = type(slot) == "number" and api.getItemCount(slot) or nil
    if type(before) ~= "number" or before <= 0
        or api.drop() ~= true or api.getItemCount(slot) ~= 0 then
        return false, "SUPPLY_RETURN_FAILED"
    end
    return true
end

local function runUnsafe(options)
    local api = options.turtle
    local maxPulls = options.maxPulls or 32
    local inventory = options.itemConfig.inventory or {}
    local torchQuota = inventory.torchRetainedCount or options.torchTarget

    local fueled, fuelCode = refuelTo(api, options.itemConfig, options.targetFuel)
    if not fueled then
        for _ = 1, maxPulls do
            local slot = firstEmptySlot(api)
            if not slot then return { ok = false, code = "NO_FUEL_SUPPLY" } end
            if api.select(slot) ~= true then return { ok = false, code = "SUPPLY_SELECT_FAILED" } end
            local pulled = api.suck()
            local count = api.getItemCount(slot)
            if pulled ~= true or type(count) ~= "number" or count <= 0 then
                return { ok = false, code = fuelCode or "NO_FUEL_SUPPLY" }
            end
            local detail = api.getItemDetail(slot)
            if detail and detail.name == "minecraft:torch" then
                -- Chest ordering is arbitrary. Keep only what fits below the
                -- configured onboard torch quota and return all excess.
                local torches = inventoryCount(api, "minecraft:torch")
                if torches == nil then return { ok = false, code = "SUPPLY_COUNT_UNAVAILABLE" } end
                if torches > torchQuota then
                    local returned, returnCode = dropCurrentSlot(api)
                    if not returned then return { ok = false, code = returnCode } end
                end
            elseif not detail or not ItemPolicy.isFuel(detail.name, options.itemConfig) then
                local before = count
                local dropped = api.drop()
                if dropped ~= true or api.getItemCount(slot) ~= 0 or before <= 0 then
                    return { ok = false, code = "SUPPLY_RETURN_FAILED" }
                end
                return { ok = false, code = "UNSUPPORTED_SUPPLY_ITEM" }
            else
                fueled, fuelCode = refuelTo(api, options.itemConfig, options.targetFuel)
                if fueled then break end
            end
        end
    end
    if not fueled then return { ok = false, code = fuelCode or "NO_FUEL_SUPPLY" } end

    local torches = inventoryCount(api, "minecraft:torch")
    if torches == nil then return { ok = false, code = "SUPPLY_COUNT_UNAVAILABLE" } end
    local pulls = 0
    local torchTarget = math.min(options.torchTarget, torchQuota)
    while torches < torchTarget and pulls < maxPulls do
        local slot = firstEmptySlot(api)
        -- The configured target is a best-effort stock level. A full turtle or
        -- exhausted chest may still meet the separately configured departure
        -- minimum, in which case service can safely continue.
        if not slot then break end
        if api.select(slot) ~= true then return { ok = false, code = "SUPPLY_SELECT_FAILED" } end
        local pulled = api.suck()
        local count = api.getItemCount(slot)
        pulls = pulls + 1
        if pulled ~= true then
            break
        end
        if type(count) ~= "number" or count <= 0 then
            return { ok = false, code = "NO_TORCHES" }
        end
        local detail = api.getItemDetail(slot)
        if detail and ItemPolicy.isFuel(detail.name, options.itemConfig) then
            local ok, code = refuelTo(api, options.itemConfig, options.targetFuel)
            if not ok then return { ok = false, code = code } end
        elseif detail and detail.name == "minecraft:torch" then
            torches = inventoryCount(api, "minecraft:torch")
            if torches == nil then return { ok = false, code = "SUPPLY_COUNT_UNAVAILABLE" } end
            if torches > torchQuota then
                local returned, returnCode = dropCurrentSlot(api)
                if not returned then return { ok = false, code = returnCode } end
            end
        else
            local dropped = api.drop()
            if dropped ~= true or api.getItemCount(slot) ~= 0 then
                return { ok = false, code = "SUPPLY_RETURN_FAILED" }
            end
            return { ok = false, code = "UNSUPPORTED_SUPPLY_ITEM" }
        end
        torches = inventoryCount(api, "minecraft:torch")
        if torches == nil then return { ok = false, code = "SUPPLY_COUNT_UNAVAILABLE" } end
    end
    if torches < options.minimumTorches then return { ok = false, code = "NO_TORCHES" } end
    local finalFuel = api.getFuelLevel()
    if not FuelLevel.isUnlimited(finalFuel)
        and (type(finalFuel) ~= "number" or finalFuel < options.targetFuel) then
        return { ok = false, code = "NO_FUEL_SUPPLY" }
    end

    -- Keep the configured physical emergency fuel quota onboard after filling
    -- the tank. This quota is distinct from the route commitment and may be
    -- consumed later by the movement safety policy.
    local fuelQuota = type(options.itemConfig.inventory) == "table"
        and options.itemConfig.inventory.fuelRetainedCount or 0
    if type(fuelQuota) ~= "number" or fuelQuota < 0
        or fuelQuota ~= math.floor(fuelQuota) then
        return { ok = false, code = "INVALID_RESUPPLY_OPTIONS" }
    end
    local onboardFuel = inventoryFuelCount(api, options.itemConfig)
    if onboardFuel == nil then return { ok = false, code = "SUPPLY_COUNT_UNAVAILABLE" } end
    local fuelPulls = 0
    while onboardFuel < fuelQuota and fuelPulls < maxPulls do
        local slot = firstEmptySlot(api)
        if not slot then return { ok = false, code = "NO_FUEL_SUPPLY" } end
        if api.select(slot) ~= true then return { ok = false, code = "SUPPLY_SELECT_FAILED" } end
        if api.suck() ~= true then return { ok = false, code = "NO_FUEL_SUPPLY" } end
        fuelPulls = fuelPulls + 1
        local amount = api.getItemCount(slot)
        local detail = api.getItemDetail(slot)
        if type(amount) ~= "number" or amount <= 0 or not detail then
            return { ok = false, code = "SUPPLY_COUNT_UNAVAILABLE" }
        end
        if detail.name == "minecraft:torch" then
            local torchCount = inventoryCount(api, "minecraft:torch")
            if torchCount == nil then return { ok = false, code = "SUPPLY_COUNT_UNAVAILABLE" } end
            if torchCount > torchQuota then
                local returned, returnCode = dropCurrentSlot(api)
                if not returned then return { ok = false, code = returnCode } end
            end
        elseif not ItemPolicy.isFuel(detail.name, options.itemConfig) then
            if api.drop() ~= true or api.getItemCount(slot) ~= 0 then
                return { ok = false, code = "SUPPLY_RETURN_FAILED" }
            end
            return { ok = false, code = "UNSUPPORTED_SUPPLY_ITEM" }
        end
        onboardFuel = inventoryFuelCount(api, options.itemConfig)
        if onboardFuel == nil then return { ok = false, code = "SUPPLY_COUNT_UNAVAILABLE" } end
    end
    if onboardFuel < fuelQuota then return { ok = false, code = "NO_FUEL_SUPPLY" } end
    torches = inventoryCount(api, "minecraft:torch")
    if torches == nil then return { ok = false, code = "SUPPLY_COUNT_UNAVAILABLE" } end
    return { ok = true, code = "RESUPPLY_COMPLETE", fuel = finalFuel, torches = torches }
end

function Resupply.run(options)
    local valid, code = validateOptions(options)
    if not valid then return { ok = false, code = code } end
    local guarded = SlotGuard.run(options.turtle, function() return runUnsafe(options) end)
    if not guarded.ok then return { ok = false, code = guarded.code } end
    return guarded.value
end

return Resupply
