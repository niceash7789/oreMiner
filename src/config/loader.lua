-- Complete V1 configuration validation and normalization boundary.
local NumericValidation = require("src.config.numeric_validation")
local Result = require("src.safety.result")

local Loader = {}

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local function invalid(message)
    return nil, Result.new(false, "CONFIG_INVALID", message)
end

local function finiteNumber(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function integerAtLeast(value, minimum)
    return finiteNumber(value) and value == math.floor(value) and value >= minimum
end

local function requireBoolean(section, field, path)
    if type(section[field]) ~= "boolean" then
        return false, path .. " must be a boolean"
    end
    return true
end

local function requireInteger(section, field, minimum, path)
    if not integerAtLeast(section[field], minimum) then
        return false, path .. " must be an integer of at least " .. minimum
    end
    return true
end

local function stringList(value, path, allowEmpty)
    if type(value) ~= "table" then return false, path .. " must be a list" end
    local count = 0
    for index, item in ipairs(value) do
        count = index
        if type(item) ~= "string" or item == "" then
            return false, path .. " must contain non-empty strings"
        end
    end
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key > count or key ~= math.floor(key) then
            return false, path .. " must be a sequence"
        end
    end
    if not allowEmpty and count == 0 then return false, path .. " must not be empty" end
    return true
end

local function quotaMap(value, path)
    if type(value) ~= "table" then return false, path .. " must be a table" end
    for itemId, quantity in pairs(value) do
        if type(itemId) ~= "string" or itemId == "" or not integerAtLeast(quantity, 0) then
            return false, path .. " must map item IDs to non-negative integers"
        end
    end
    return true
end

local function validate(raw)
    if type(raw) ~= "table" then return false, "configuration must return a table" end
    if raw.schemaVersion ~= 1 then return false, "schemaVersion must be 1" end

    local sectionNames = {
        "mining", "inventory", "fuel", "ore", "base", "supplies",
        "lighting", "safety", "features", "paving",
    }
    for _, name in ipairs(sectionNames) do
        if type(raw[name]) ~= "table" then
            return false, name .. " must be a table"
        end
    end

    local numericOk, numericReason = NumericValidation.validate(raw)
    if not numericOk then return false, numericReason end

    local mining = raw.mining
    for _, item in ipairs({
        { "floorCount", 1 }, { "surfaceEntryLength", 1 },
        { "stairStepsPerFloor", 1 }, { "stairWidth", 1 },
        { "stairHeight", 1 }, { "branchLength", 1 },
        { "branchPairs", 1 }, { "branchSpacing", 2 },
        { "tunnelHeight", 1 },
    }) do
        local ok, reason = requireInteger(mining, item[1], item[2], "mining." .. item[1])
        if not ok then return false, reason end
    end
    local ok, reason = requireBoolean(mining, "scanMainTunnel", "mining.scanMainTunnel")
    if not ok then return false, reason end
    if mining.floorMainTurn ~= "right" then
        return false, "mining.floorMainTurn must be right in V1"
    end

    local inventory = raw.inventory
    ok, reason = requireInteger(inventory, "returnThreshold", 1, "inventory.returnThreshold")
    if not ok then return false, reason end
    for _, field in ipairs({ "autoConsolidate", "autoUnload" }) do
        ok, reason = requireBoolean(inventory, field, "inventory." .. field)
        if not ok then return false, reason end
    end
    ok, reason = quotaMap(inventory.keep, "inventory.keep")
    if not ok then return false, reason end
    for _, itemId in ipairs({ "minecraft:coal", "minecraft:torch", "minecraft:cobblestone" }) do
        if not integerAtLeast(inventory.keep[itemId], 0) then
            return false, "inventory.keep must define " .. itemId
        end
    end

    local fuel = raw.fuel
    ok, reason = requireBoolean(fuel, "autoRefuel", "fuel.autoRefuel")
    if not ok then return false, reason end
    ok, reason = requireInteger(fuel, "reserve", 0, "fuel.reserve")
    if not ok then return false, reason end
    ok, reason = stringList(fuel.allowedItems, "fuel.allowedItems", false)
    if not ok then return false, reason end

    local ore = raw.ore
    ok, reason = requireBoolean(ore, "enabled", "ore.enabled")
    if not ok then return false, reason end
    if ore.mode ~= "all" and ore.mode ~= "whitelist"
        and ore.mode ~= "blacklist" and ore.mode ~= "valuable" then
        return false, "ore.mode is unsupported"
    end
    for _, field in ipairs({
        "names", "tags", "namePatterns", "ignoreNames", "ignoreTags", "valuableNames",
    }) do
        ok, reason = stringList(ore[field], "ore." .. field, true)
        if not ok then return false, reason end
    end
    for _, pattern in ipairs(ore.namePatterns) do
        if not pcall(string.find, "", pattern) then
            return false, "ore.namePatterns contains an invalid Lua pattern"
        end
    end
    for _, field in ipairs({ "maxBlocks", "maxRadius" }) do
        ok, reason = requireInteger(ore, field, 1, "ore." .. field)
        if not ok then return false, reason end
    end

    ok, reason = requireBoolean(raw.base, "separateBulk", "base.separateBulk")
    if not ok then return false, reason end
    if raw.base.supply ~= "left" or raw.base.primaryOutput ~= "right"
        or raw.base.bulkOutput ~= "back" then
        return false, "base chest sides must be left/right/back in V1"
    end
    ok, reason = stringList(raw.base.acceptedChestBlockIds,
        "base.acceptedChestBlockIds", false)
    if not ok then return false, reason end

    for _, field in ipairs({ "torchTarget", "minimumTorchesToDepart" }) do
        ok, reason = requireInteger(raw.supplies, field, 0, "supplies." .. field)
        if not ok then return false, reason end
    end
    ok, reason = stringList(raw.supplies.bulkNames, "supplies.bulkNames", false)
    if not ok then return false, reason end

    for _, field in ipairs({ "enabled", "skipLandingSlice" }) do
        ok, reason = requireBoolean(raw.lighting, field, "lighting." .. field)
        if not ok then return false, reason end
    end
    if raw.lighting.side ~= "right" then
        return false, "lighting.side must be right in V1"
    end
    ok, reason = stringList(raw.lighting.itemNames, "lighting.itemNames", false)
    if not ok then return false, reason end
    for _, field in ipairs({ "stairInterval", "tunnelInterval" }) do
        ok, reason = requireInteger(raw.lighting, field, 1, "lighting." .. field)
        if not ok then return false, reason end
    end
    ok, reason = requireInteger(raw.lighting, "wallHeight", 0, "lighting.wallHeight")
    if not ok then return false, reason end

    for _, field in ipairs({ "moveRetries", "digRetries", "entityRetries" }) do
        ok, reason = requireInteger(raw.safety, field, 1, "safety." .. field)
        if not ok then return false, reason end
    end
    if not finiteNumber(raw.safety.digTimeLimit) or raw.safety.digTimeLimit <= 0 then
        return false, "safety.digTimeLimit must be positive"
    end
    if not finiteNumber(raw.safety.retryDelay) or raw.safety.retryDelay < 0 then
        return false, "safety.retryDelay must be non-negative"
    end
    ok, reason = requireBoolean(raw.safety, "stopOnLiquid", "safety.stopOnLiquid")
    if not ok then return false, reason end

    for _, field in ipairs({ "paving", "persistence", "autoResupply", "torches" }) do
        ok, reason = requireBoolean(raw.features, field, "features." .. field)
        if not ok then return false, reason end
    end
    ok, reason = stringList(raw.paving.allowedItems, "paving.allowedItems", false)
    if not ok then return false, reason end
    ok, reason = requireInteger(raw.paving, "retainedTarget", 0, "paving.retainedTarget")
    if not ok then return false, reason end
    return true
end

function Loader.normalize(raw)
    local ok, reason = validate(raw)
    if not ok then return invalid(reason) end

    local normalized = copy(raw)
    normalized.branch_length = normalized.mining.branchLength
    normalized.num_branches = normalized.mining.branchPairs
    normalized.spacing = normalized.mining.branchSpacing
    normalized.fuel_reserve = normalized.fuel.reserve
    normalized.auto_refuel_coal = normalized.fuel.autoRefuel
    normalized.pave = normalized.features.paving
    normalized.vein_mine = normalized.ore.enabled

    normalized.inventory.retainedItems = copy(normalized.inventory.keep)
    normalized.inventory.fuelRetainedCount = normalized.inventory.keep["minecraft:coal"]
    normalized.inventory.torchRetainedCount = normalized.inventory.keep["minecraft:torch"]
    normalized.inventory.protectedItems = {}
    normalized.paving.enabled = normalized.features.paving
    normalized.paving.retainedCount = normalized.paving.retainedTarget
    normalized.paving.protectedItems = {}

    return normalized, Result.new(true, "CONFIG_VALID")
end

return Loader
