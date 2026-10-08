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
config.mining = { branchSpacing = 1 }
rejected(config, "nested branch spacing below two should fail")
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
