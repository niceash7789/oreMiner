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
    idle = true,
    mining = true,
    returning = true,
    servicing = true,
    resuming = true,
    complete = true,
    error = true,
}

-- Phase labels currently specified by the saved-state model or active baseline.
-- Later route implementations can extend this set alongside their plan entry.
Contracts.PHASES = {
    active_baseline = true,
    surface_entry = true,
    stairs = true,
    main_shaft = true,
    junction = true,
    branch_outbound_lower = true,
    branch_turnaround = true,
    branch_upper_return = true,
    branch_lower_return = true,
    branch_return_to_junction = true,
}

Contracts.POSE_CERTAINTIES = {
    known = true,
    uncertain = true,
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

function Contracts.isRunStatus(status)
    return Contracts.RUN_STATUSES[status] == true
end

function Contracts.isPhase(phase)
    return Contracts.PHASES[phase] == true
end

function Contracts.isWorkDomain(domain)
    return Contracts.WORK_DOMAINS[domain] == true
end

function Contracts.isPoseCertainty(certainty)
    return Contracts.POSE_CERTAINTIES[certainty] == true
end

return Contracts
