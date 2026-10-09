local Loader = require("src.config.loader")

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local source = require("config")
local normalized, result = Loader.normalize(source)
assert(result.ok and result.code == "CONFIG_VALID")
assert(normalized ~= source and normalized.mining ~= source.mining,
    "normalization must not mutate the loaded config table")
assert(normalized.branch_length == 30 and normalized.num_branches == 20
    and normalized.spacing == 3 and normalized.fuel_reserve == 100)
assert(normalized.pave == false and normalized.vein_mine == true)
assert(normalized.inventory.retainedItems["minecraft:cobblestone"] == 64)
assert(normalized.inventory.fuelRetainedCount == 64
    and normalized.inventory.torchRetainedCount == 64)
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
rejected(function(config) config.mining = nil end, "mining must be a table")
rejected(function(config) config.mining.floorCount = 0 end, "floorCount")
rejected(function(config) config.mining.surfaceEntryLength = 5 end, "surfaceEntryLength")
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
