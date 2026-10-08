-- Shared contracts for single-turtle run state and safety outcomes.
-- Pose is local integer block coordinates; facing is north/east/south/west = 0..3.
local Contracts = {}

Contracts.FACING = {
    NORTH = 0,
    EAST = 1,
    SOUTH = 2,
    WEST = 3,
}

-- Persisted work domains and top-level run statuses are separate concepts.
Contracts.WORK_DOMAINS = {
    shaft = true,
    floor = true,
    ore = true,
    service = true,
}

Contracts.RUN_STATUSES = {
    mining = true,
    complete = true,
    error = true,
}

-- Fatal codes from MINER_PLAN.md's failure/recovery contract.
Contracts.ERROR_CODES = {
    NO_FUEL = true,
    NO_FUEL_SUPPLY = true,
    NO_TORCHES = true,
    CHEST_FULL = true,
    NO_SUPPLY_CHEST = true,
    NO_OUTPUT_CHEST = true,
    NO_BULK_CHEST = true,
    EJECT_FAILED = true,
    UNLOAD_FAILED = true,
    INVENTORY_CRITICAL = true,
    BLOCKED = true,
    UNBREAKABLE_BLOCK = true,
    ENTITY_BLOCKED = true,
    LIQUID = true,
    VEIN_RETURN_BLOCKED = true,
    POSITION_ERROR = true,
    POSITION_UNCERTAIN = true,
    STATE_CORRUPT = true,
    CONFIG_INVALID = true,
}

local function integer(value)
    return type(value) == "number" and value ~= math.huge and value ~= -math.huge
        and value == math.floor(value)
end

function Contracts.isPose(pose)
    return type(pose) == "table"
        and integer(pose.x)
        and integer(pose.y)
        and integer(pose.z)
        and integer(pose.facing)
        and pose.facing >= Contracts.FACING.NORTH
        and pose.facing <= Contracts.FACING.WEST
end

function Contracts.isResult(result)
    return type(result) == "table"
        and type(result.ok) == "boolean"
        and type(result.code) == "string"
        and #result.code > 0
        and (result.message == nil or type(result.message) == "string")
        and (result.retryable == nil or type(result.retryable) == "boolean")
end

function Contracts.isFatalCode(code)
    return Contracts.ERROR_CODES[code] == true
end

return Contracts
