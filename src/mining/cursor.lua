-- Durable logical cursor for the active single-floor baseline.
-- This describes the next bounded unit of work; it does not resume that work.
local Cursor = {}

local PHASE_ACTIONS = {
    main_shaft = { mine_main_cell = true },
    junction = { turn_to_left_branch = true, restore_main_facing = true },
    branch_outbound_lower = { mine_branch_cell = true },
    branch_turnaround = { prepare_branch_return = true },
    branch_upper_return = { scan_and_return_branch_cell = true },
    branch_lower_return = { return_branch_cell = true },
    branch_return_to_junction = { descend_to_junction = true },
}

local function integer(value)
    return type(value) == "number" and value ~= math.huge and value ~= -math.huge
        and value == math.floor(value)
end

local function nonNegativeInteger(value)
    return integer(value) and value >= 0
end

local function identifier(value)
    return type(value) == "string" and #value > 0
        and value:match("^[a-z0-9_-]+$") ~= nil
end

function Cursor.validate(progress)
    if type(progress) ~= "table"
        or progress.workDomain ~= "floor"
        or not identifier(progress.workUnitId)
        or not nonNegativeInteger(progress.floor)
        or not nonNegativeInteger(progress.stairSegment)
        or not nonNegativeInteger(progress.stairStep)
        or not integer(progress.branchPair) or progress.branchPair < 1
        or not nonNegativeInteger(progress.offset)
        or not nonNegativeInteger(progress.mainOffset)
        or (progress.side ~= "none" and progress.side ~= "left" and progress.side ~= "right")
        or type(progress.phase) ~= "string"
        or type(progress.nextAction) ~= "string" then
        return false
    end

    local actions = PHASE_ACTIONS[progress.phase]
    if not actions or actions[progress.nextAction] ~= true then return false end
    if progress.phase == "main_shaft" or progress.phase == "junction" then
        return progress.side == "none"
    end
    return progress.side == "left" or progress.side == "right"
end

local function create(branchPair, side, phase, offset, mainOffset, nextAction, suffix)
    if not integer(branchPair) or branchPair < 1
        or type(side) ~= "string"
        or type(phase) ~= "string"
        or not nonNegativeInteger(offset)
        or not nonNegativeInteger(mainOffset)
        or type(nextAction) ~= "string"
        or type(suffix) ~= "string" then
        return nil, "INVALID_MINING_CURSOR"
    end
    local progress = {
        workDomain = "floor",
        workUnitId = string.format("surface-pair-%d-%s", branchPair, suffix),
        floor = 0,
        stairSegment = 0,
        stairStep = 0,
        branchPair = branchPair,
        side = side,
        phase = phase,
        offset = offset,
        mainOffset = mainOffset,
        nextAction = nextAction,
    }
    if not Cursor.validate(progress) then return nil, "INVALID_MINING_CURSOR" end
    return progress
end

function Cursor.initial()
    return Cursor.mainShaft(1, 1, 0)
end

function Cursor.mainShaft(branchPair, step, mainOffset)
    if not integer(step) or step < 1 then return nil, "INVALID_MINING_CURSOR" end
    return create(branchPair, "none", "main_shaft", step - 1, mainOffset,
        "mine_main_cell", "main-" .. step)
end

function Cursor.junction(branchPair, mainOffset, nextAction)
    if type(nextAction) ~= "string" then return nil, "INVALID_MINING_CURSOR" end
    return create(branchPair, "none", "junction", 0, mainOffset, nextAction,
        "junction-" .. nextAction)
end

function Cursor.branch(branchPair, side, phase, offset, mainOffset, nextAction)
    if type(side) ~= "string" or type(phase) ~= "string"
        or not nonNegativeInteger(offset) then
        return nil, "INVALID_MINING_CURSOR"
    end
    return create(branchPair, side, phase, offset, mainOffset, nextAction,
        string.format("%s-%s-%d", side, phase, offset))
end

return Cursor
