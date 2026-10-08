local NumericValidation = {}

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
    if not mining or not inventory or not fuel or not supplies or not base or not lighting then
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

    local fields = {
        { "floorCount", "mining.floorCount" },
        { "stairStepsPerFloor", "mining.stairStepsPerFloor" },
        { "branchLength", "mining.branchLength" },
        { "branchPairs", "mining.branchPairs" },
    }
    local ok, reason = checkPositiveFields(mining, fields)
    if not ok then return false, reason end
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
    if mining.branchSpacing ~= nil and not integerAtLeast(mining.branchSpacing, 2) then
        return false, "mining.branchSpacing must be an integer of at least 2"
    end

    -- The active baseline still uses these names while configuration migrates.
    ok, reason = checkPositiveFields(config, {
        { "branch_length", "branch_length" },
        { "num_branches", "num_branches" },
    })
    if not ok then return false, reason end
    if config.spacing ~= nil and not integerAtLeast(config.spacing, 2) then
        return false, "spacing must be an integer of at least 2"
    end

    local function checkThreshold(value, name)
        if value ~= nil and (not integerAtLeast(value, 1) or value > 15) then
            return false, name .. " must be an integer from 1 through 15"
        end
        return true
    end
    ok, reason = checkThreshold(inventory.returnThreshold, "inventory.returnThreshold")
    if not ok then return false, reason end
    ok, reason = checkThreshold(inventory.pressureThreshold, "inventory.pressureThreshold")
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
