local ItemPolicy = {}

local function contains(itemIds, itemId)
    if type(itemIds) ~= "table" or type(itemId) ~= "string" then
        return false
    end

    for _, configuredId in ipairs(itemIds) do
        if configuredId == itemId then
            return true
        end
    end

    return false
end

function ItemPolicy.isFuel(itemId, config)
    return contains(config and config.fuel and config.fuel.allowedItems, itemId)
end

function ItemPolicy.isPaving(itemId, config)
    if not config or not config.paving or config.paving.enabled ~= true then
        return false
    end
    return contains(config and config.paving and config.paving.allowedItems, itemId)
end

function ItemPolicy.isBulk(itemId, config)
    return contains(config and config.supplies and config.supplies.bulkNames, itemId)
end

function ItemPolicy.isSupply(itemId, config)
    return ItemPolicy.retainedCount(itemId, config) > 0
end

function ItemPolicy.retainedCount(itemId, config)
    local configured = config and config.inventory and config.inventory.retainedItems
    if itemId == "minecraft:cobblestone" then
        if type(configured) == "table" and type(configured[itemId]) == "number" then
            return math.max(0, configured[itemId])
        end
        return 64
    end
    if type(configured) == "table" and type(configured[itemId]) == "number" then
        return math.max(0, configured[itemId])
    end
    if ItemPolicy.isFuel(itemId, config) then
        return math.max(0, config.inventory and config.inventory.fuelRetainedCount or 64)
    end
    if itemId == "minecraft:torch" then
        return math.max(0, config.inventory and config.inventory.torchRetainedCount or 64)
    end
    return 0
end

function ItemPolicy.mayConsumeForPaving(itemId, config, availableCount)
    if not ItemPolicy.isPaving(itemId, config)
        or ItemPolicy.isProtected(itemId, config) then
        return false
    end
    local retained = ItemPolicy.retainedCount(itemId, config)
    return type(availableCount) == "number" and availableCount > retained
end

function ItemPolicy.isProtected(itemId, config)
    if ItemPolicy.isFuel(itemId, config) or itemId == "minecraft:torch" then return true end
    if type(itemId) ~= "string" then return true end
    if ItemPolicy.isFuel(itemId, config)
        or contains(config.paving and config.paving.protectedItems, itemId)
        or contains(config.inventory and config.inventory.protectedItems, itemId) then
        return true
    end
    local oreConfig = config and config.ore
    if type(oreConfig) ~= "table" then return true end
    if itemId == "minecraft:cobblestone" then return false end
    if ItemPolicy.isPaving(itemId, config)
        and ItemPolicy.retainedCount(itemId, config) > 0 then
        return false
    end
    if itemId:find("_ore", 1, true) then return true end
    if contains(oreConfig.ignoreNames, itemId) then return false end
    if contains(oreConfig.names, itemId) or contains(oreConfig.valuableNames, itemId) then return true end
    if not contains(config.paving and config.paving.allowedItems, itemId) then return true end
    local patterns = oreConfig.namePatterns or { "_ore$" }
    for _, pattern in ipairs(patterns) do
        local ok, matched = pcall(string.find, itemId, pattern)
        if ok and matched then return true end
    end
    return ItemPolicy.retainedCount(itemId, config) > 0
end

return ItemPolicy
