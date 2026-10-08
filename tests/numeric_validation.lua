local Validation = require("src.config.numeric_validation")

local function activeConfig()
    return {
        branch_length = 30,
        num_branches = 20,
        spacing = 3,
        fuel_reserve = 100,
        inventory = {
            pressureThreshold = 14,
            retainedItems = { ["minecraft:cobblestone"] = 64 },
        },
    }
end

local function accepted(config, message)
    local ok, reason = Validation.validate(config)
    assert(ok, message or reason)
end

local function rejected(config, message)
    local ok, reason = Validation.validate(config)
    assert(not ok, message or "invalid numeric configuration was accepted")
    return reason
end

accepted(activeConfig(), "active defaults should validate")
for _, key in ipairs({ "branch_length", "num_branches" }) do
    for _, value in ipairs({ 0, -1, 1.5 }) do
        local config = activeConfig()
        config[key] = value
        rejected(config, key .. " should reject " .. value)
    end
end
for _, value in ipairs({ 1, 1.5, 0 }) do
    local config = activeConfig()
    config.spacing = value
    rejected(config, "spacing should reject " .. value)
end

for _, field in ipairs({ "floorCount", "stairStepsPerFloor", "branchLength", "branchPairs" }) do
    for _, value in ipairs({ 0, -1, 1.5 }) do
        local config = activeConfig()
        config.mining = { [field] = value }
        rejected(config, field .. " should reject " .. value)
    end
end
local config = activeConfig()
config.mining = { stairStepsPerFloor = 8 }
accepted(config, "V1 stair slice count of eight should validate")
for _, value in ipairs({ 1, 7, 9, 16 }) do
    config = activeConfig()
    config.mining = { stairStepsPerFloor = value }
    local reason = rejected(config, "V1 should reject stair slice count " .. value)
    assert(reason == "mining.stairStepsPerFloor must be 8 in V1", "unexpected stair count error")
end
config = activeConfig()
config.mining = { surfaceEntryLength = 4, stairWidth = 3, stairHeight = 3 }
accepted(config, "V1 fixed surface entry and stair geometry should validate")
config = activeConfig()
config.mining = { floorMainTurn = "right" }
accepted(config, "V1 floor main turn should be right")
for _, value in ipairs({ "left", "forward", "back", 1, false }) do
    config = activeConfig()
    config.mining = { floorMainTurn = value }
    local reason = rejected(config, "V1 should reject floor main turn " .. tostring(value))
    assert(reason == "mining.floorMainTurn must be right in V1", "unexpected floor main turn error")
end
for _, item in ipairs({
    { "surfaceEntryLength", 4, { 0, 3, 5, 4.5 } },
    { "stairWidth", 3, { 0, 2, 4, 3.5 } },
    { "stairHeight", 3, { 0, 2, 4, 3.5 } },
}) do
    for _, value in ipairs(item[3]) do
        config = activeConfig()
        config.mining = { [item[1]] = value }
        local reason = rejected(config, "V1 should reject unsupported " .. item[1] .. " " .. value)
        assert(reason == "mining." .. item[1] .. " must be " .. item[2] .. " in V1", "unexpected fixed geometry error")
    end
end
config = activeConfig()
config.mining = { branchSpacing = 1 }
rejected(config, "nested branch spacing below two should fail")
config = activeConfig()
accepted(config, "omitted base sides should remain valid during schema migration")
config.base = { supply = "left", primaryOutput = "right", bulkOutput = "back" }
accepted(config, "fixed V1 chest sides should validate")
for _, item in ipairs({
    { "supply", "left", { "right", "back", "forward", 1 } },
    { "primaryOutput", "right", { "left", "back", "forward", false } },
    { "bulkOutput", "back", { "left", "right", "forward", 1 } },
}) do
    for _, value in ipairs(item[3]) do
        config = activeConfig()
        config.base = { [item[1]] = value }
        local reason = rejected(config, "V1 should reject unsupported base." .. item[1] .. " side")
        assert(reason == "base." .. item[1] .. " must be " .. item[2] .. " in V1", "unexpected base side error")
    end
end
config = activeConfig()
config.base = false
rejected(config, "base section must be a table when supplied")
config = activeConfig()
config.lighting = { side = "right" }
accepted(config, "V1 lighting side should be right")
for _, value in ipairs({ "left", "forward", "back", "none", 1, false }) do
    config = activeConfig()
    config.lighting = { side = value }
    local reason = rejected(config, "V1 should reject unsupported lighting side " .. tostring(value))
    assert(reason == "lighting.side must be right in V1", "unexpected lighting side error")
end
config = activeConfig()
config.lighting = false
rejected(config, "lighting section must be a table when supplied")
for _, value in ipairs({ 0, 16, 2.5 }) do
    config = activeConfig()
    config.inventory.pressureThreshold = value
    rejected(config, "threshold should reject " .. value)
end
for _, value in ipairs({ -1, 1.5 }) do
    config = activeConfig()
    config.fuel_reserve = value
    rejected(config, "fuel reserve should reject " .. value)
    config = activeConfig()
    config.inventory.retainedItems["minecraft:cobblestone"] = value
    rejected(config, "quota should reject " .. value)
end

print("numeric configuration validation checks passed")
