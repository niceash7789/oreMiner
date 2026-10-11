local Loader = require("src.config.loader")

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local source = require("tests.config_fixture")
local normalized, result = Loader.normalize(source)
assert(result.ok and result.code == "CONFIG_VALID")
assert(normalized ~= source and normalized.mining ~= source.mining,
    "normalization must not mutate the loaded config table")
assert(normalized.branch_length == source.mining.branchLength
    and normalized.num_branches == source.mining.branchPairs
    and normalized.spacing == source.mining.branchSpacing
    and normalized.fuel_reserve == source.fuel.reserve)
assert(normalized.pave == source.features.paving
    and normalized.vein_mine == source.ore.enabled)
assert(normalized.mining.firstFloorDepthOffset == 0
    and source.mining.firstFloorDepthOffset == nil,
    "older V1 configurations should keep the original first-floor depth")
local offsetConfig = copy(source)
offsetConfig.mining.firstFloorDepthOffset = 3
local offsetNormalized, offsetResult = Loader.normalize(offsetConfig)
assert(offsetResult.ok and offsetNormalized.mining.firstFloorDepthOffset == 3)
assert(normalized.inventory.retainedItems["minecraft:cobblestone"]
    == source.inventory.keep["minecraft:cobblestone"])
assert(normalized.inventory.fuelRetainedCount == source.inventory.keep["minecraft:coal"]
    and normalized.inventory.torchRetainedCount == source.inventory.keep["minecraft:torch"])
assert(source.branch_length == nil and source.inventory.retainedItems == nil,
    "compatibility fields must exist only on the normalized copy")

local function rejected(mutator, expected)
    local candidate = copy(source)
    mutator(candidate)
    local loaded, outcome = Loader.normalize(candidate)
    assert(loaded == nil and not outcome.ok and outcome.code == "CONFIG_INVALID")
    assert(outcome.message:find(expected, 1, true),
        "unexpected config error: " .. tostring(outcome.message))
end

rejected(function(config) config.schemaVersion = 2 end, "schemaVersion")
rejected(function(config) config.workers = 2 end, "V1 runs one turtle")
rejected(function(config) config.workerCount = 1 end, "V1 runs one turtle")
rejected(function(config) config.turtleCount = 2 end, "V1 runs one turtle")
rejected(function(config) config.fleet = {} end, "V1 runs one turtle")
rejected(function(config) config.mining = nil end, "mining must be a table")
rejected(function(config) config.mining.floorCount = 0 end, "floorCount")
rejected(function(config) config.mining.surfaceEntryLength = 5 end, "surfaceEntryLength")
rejected(function(config) config.mining.firstFloorDepthOffset = -1 end, "firstFloorDepthOffset")
rejected(function(config) config.mining.firstFloorDepthOffset = 61 end, "firstFloorDepthOffset")
rejected(function(config)
    config.mining.stairStepsPerFloor = 63
    config.mining.firstFloorDepthOffset = 2
end, "first floor stair steps")
rejected(function(config) config.mining.floorMainTurn = nil end, "floorMainTurn")
rejected(function(config) config.inventory.autoUnload = "yes" end, "autoUnload")
rejected(function(config) config.inventory.keep["minecraft:torch"] = nil end,
    "inventory.keep must define minecraft:torch")
rejected(function(config) config.fuel.allowedItems = {} end, "fuel.allowedItems")
rejected(function(config) config.ore.mode = "everything" end, "ore.mode")
rejected(function(config) config.ore.namePatterns = { "[" } end, "invalid Lua pattern")
rejected(function(config) config.base.acceptedChestBlockIds = { [2] = "minecraft:chest" } end,
    "must be a sequence")
rejected(function(config) config.base.supply = nil end, "base chest sides")
rejected(function(config) config.lighting.side = nil end, "lighting.side")
rejected(function(config) config.safety.retryDelay = -0.1 end, "retryDelay")
rejected(function(config) config.features.persistence = nil end, "features.persistence")

print("configuration loader checks passed")
