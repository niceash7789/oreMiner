local NumericValidation = {}

local MAX_BRANCH_LENGTH = 256
local MAX_BRANCH_PAIRS = 100
local MAX_BRANCH_SPACING = 64

local function integerAtLeast(value, minimum)
    return type(value) == "number"
        and value ~= math.huge
        and value ~= -math.huge
        and value == math.floor(value)
        and value >= minimum
end

local function nonNegative(value)
    return type(value) == "number"
        and value ~= math.huge
        and value ~= -math.huge
        and value == math.floor(value)
        and value >= 0
end

local function integerInRange(value, minimum, maximum)
    return integerAtLeast(value, minimum) and value <= maximum
end

local function tableAt(config, key)
    local value = config[key]
    if value == nil then return {} end
    if type(value) ~= "table" then return nil end
    return value
end

local function checkPositiveFields(config, fields)
    for _, item in ipairs(fields) do
        local value = config[item[1]]
        if value ~= nil and not integerAtLeast(value, 1) then
            return false, item[2] .. " must be a positive integer"
        end
    end
    return true
end

local function checkQuotas(values, name)
    if type(values) ~= "table" then return false, name .. " must be a table" end
    for item, quantity in pairs(values) do
        if type(item) ~= "string" or not nonNegative(quantity) then
            return false, name .. " quantities must be non-negative integers"
        end
    end
    return true
end

function NumericValidation.validate(config)
    if type(config) ~= "table" then return false, "configuration must be a table" end
    local mining = tableAt(config, "mining")
    local inventory = tableAt(config, "inventory")
    local fuel = tableAt(config, "fuel")
    local supplies = tableAt(config, "supplies")
    local base = tableAt(config, "base")
    local lighting = tableAt(config, "lighting")
    local ore = tableAt(config, "ore")
    if not mining or not inventory or not fuel or not supplies or not base or not lighting or not ore then
        return false, "configuration sections must be tables"
    end

    if lighting.side ~= nil and lighting.side ~= "right" then
        return false, "lighting.side must be right in V1"
    end

    local fixedBaseSides = {
        { "supply", "left" },
        { "primaryOutput", "right" },
        { "bulkOutput", "back" },
    }
    for _, item in ipairs(fixedBaseSides) do
        local value = base[item[1]]
        if value ~= nil and value ~= item[2] then
            return false, "base." .. item[1] .. " must be " .. item[2] .. " in V1"
        end
    end
    if base.separateBulk ~= nil and type(base.separateBulk) ~= "boolean" then
        return false, "base.separateBulk must be a boolean"
    end
    if supplies.bulkNames ~= nil then
        if type(supplies.bulkNames) ~= "table" then
            return false, "supplies.bulkNames must be a table"
        end
        for _, itemId in ipairs(supplies.bulkNames) do
            if type(itemId) ~= "string" or itemId == "" then
                return false, "supplies.bulkNames must contain non-empty item IDs"
            end
        end
    end
    if ore.availableTagKeys ~= nil then
        if type(ore.availableTagKeys) ~= "table" then
            return false, "ore.availableTagKeys must be a table"
        end
        for _, tag in ipairs(ore.availableTagKeys) do
            if type(tag) ~= "string" or tag == "" then
                return false, "ore.availableTagKeys must contain non-empty tag keys"
            end
        end
    end

    local fields = {
        { "floorCount", "mining.floorCount" },
        { "stairStepsPerFloor", "mining.stairStepsPerFloor" },
    }
    local ok, reason = checkPositiveFields(mining, fields)
    if not ok then return false, reason end
    if mining.branchLength ~= nil and not integerInRange(mining.branchLength, 1, MAX_BRANCH_LENGTH) then
        return false, "mining.branchLength must be an integer from 1 through " .. MAX_BRANCH_LENGTH
    end
    if mining.branchPairs ~= nil and not integerInRange(mining.branchPairs, 1, MAX_BRANCH_PAIRS) then
        return false, "mining.branchPairs must be an integer from 1 through " .. MAX_BRANCH_PAIRS
    end
    if mining.tunnelHeight ~= nil and mining.tunnelHeight ~= 2 then
        return false, "mining.tunnelHeight must be 2 in V1"
    end
    if mining.stairStepsPerFloor ~= nil and mining.stairStepsPerFloor ~= 8 then
        return false, "mining.stairStepsPerFloor must be 8 in V1"
    end
    if mining.floorMainTurn ~= nil and mining.floorMainTurn ~= "right" then
        return false, "mining.floorMainTurn must be right in V1"
    end
    local fixedGeometry = {
        { "surfaceEntryLength", 4 },
        { "stairWidth", 3 },
        { "stairHeight", 3 },
    }
    for _, item in ipairs(fixedGeometry) do
        local value = mining[item[1]]
        if value ~= nil and value ~= item[2] then
            return false, "mining." .. item[1] .. " must be " .. item[2] .. " in V1"
        end
    end
    if mining.branchSpacing ~= nil and not integerInRange(mining.branchSpacing, 2, MAX_BRANCH_SPACING) then
        return false, "mining.branchSpacing must be an integer from 2 through " .. MAX_BRANCH_SPACING
    end

    -- The active baseline still uses these names while configuration migrates.
    if config.branch_length ~= nil and not integerInRange(config.branch_length, 1, MAX_BRANCH_LENGTH) then
        return false, "branch_length must be an integer from 1 through " .. MAX_BRANCH_LENGTH
    end
    if config.num_branches ~= nil and not integerInRange(config.num_branches, 1, MAX_BRANCH_PAIRS) then
        return false, "num_branches must be an integer from 1 through " .. MAX_BRANCH_PAIRS
    end
    if config.spacing ~= nil and not integerInRange(config.spacing, 2, MAX_BRANCH_SPACING) then
        return false, "spacing must be an integer from 2 through " .. MAX_BRANCH_SPACING
    end

    local function checkThreshold(value, name)
        if value ~= nil and (not integerAtLeast(value, 1) or value > 15) then
            return false, name .. " must be an integer from 1 through 15"
        end
        return true
    end
    ok, reason = checkThreshold(inventory.returnThreshold, "inventory.returnThreshold")
    if not ok then return false, reason end
    local function checkReserve(value, name)
        if value ~= nil and not nonNegative(value) then
            return false, name .. " must be a non-negative integer"
        end
        return true
    end
    ok, reason = checkReserve(fuel.reserve, "fuel.reserve")
    if not ok then return false, reason end
    ok, reason = checkReserve(config.fuel_reserve, "fuel_reserve")
    if not ok then return false, reason end
    ok, reason = checkReserve(supplies.torchTarget, "supplies.torchTarget")
    if not ok then return false, reason end
    ok, reason = checkReserve(supplies.minimumTorchesToDepart, "supplies.minimumTorchesToDepart")
    if not ok then return false, reason end

    if inventory.keep ~= nil then
        ok, reason = checkQuotas(inventory.keep, "inventory.keep")
        if not ok then return false, reason end
    end
    if inventory.retainedItems ~= nil then
        ok, reason = checkQuotas(inventory.retainedItems, "inventory.retainedItems")
        if not ok then return false, reason end
    end
    return true
end

return NumericValidation
