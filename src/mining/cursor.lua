-- Durable logical cursor for the next bounded route or mining unit.
local Cursor = {}

local PHASE_ACTIONS = {
    surface_entry = { enter_surface = true },
    stairs = {
        cross_landing = true,
        descend_stair_slice = true,
        prepare_landing = true,
    },
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
        or (progress.workDomain ~= "floor" and progress.workDomain ~= "shaft")
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
    if progress.phase == "surface_entry" or progress.phase == "stairs" then
        return progress.workDomain == "shaft" and progress.floor >= 1
            and progress.stairSegment == progress.floor - 1
            and progress.side == "none"
    end
    if progress.workDomain ~= "floor" then return false end
    if progress.phase == "main_shaft" or progress.phase == "junction" then
        return progress.side == "none"
    end
    return progress.side == "left" or progress.side == "right"
end

local function create(branchPair, side, phase, offset, mainOffset, nextAction, suffix, floor)
    if not integer(branchPair) or branchPair < 1
        or type(side) ~= "string"
        or type(phase) ~= "string"
        or not nonNegativeInteger(offset)
        or not nonNegativeInteger(mainOffset)
        or type(nextAction) ~= "string"
        or type(suffix) ~= "string"
        or (floor ~= nil and not nonNegativeInteger(floor)) then
        return nil, "INVALID_MINING_CURSOR"
    end
    local progress = {
        workDomain = "floor",
        workUnitId = floor and floor > 0
            and string.format("floor-%d-pair-%d-%s", floor, branchPair, suffix)
            or string.format("surface-pair-%d-%s", branchPair, suffix),
        floor = floor or 0,
        stairSegment = floor and math.max(0, floor - 1) or 0,
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

-- Route cursor used before surface entry and before each bounded stair/landing
-- unit. A committed physical action remains separately protected by P02's
-- pending-action record; this cursor does not infer pose after a crash.
function Cursor.stairs(floor, stairStep, nextAction)
    if not integer(floor) or floor < 1 or not nonNegativeInteger(stairStep)
        or (nextAction ~= "enter_surface" and nextAction ~= "cross_landing"
            and nextAction ~= "descend_stair_slice" and nextAction ~= "prepare_landing") then
        return nil, "INVALID_MINING_CURSOR"
    end
    local phase = nextAction == "enter_surface" and "surface_entry" or "stairs"
    local progress = {
        workDomain = "shaft",
        workUnitId = string.format("floor-%d-stairs-%d-%s", floor, stairStep, nextAction),
        floor = floor,
        stairSegment = floor - 1,
        stairStep = stairStep,
        branchPair = 1,
        side = "none",
        phase = phase,
        offset = stairStep,
        mainOffset = 0,
        nextAction = nextAction,
    }
    if not Cursor.validate(progress) then return nil, "INVALID_MINING_CURSOR" end
    return progress
end

function Cursor.mainShaft(branchPair, step, mainOffset, floor)
    if not integer(step) or step < 1 then return nil, "INVALID_MINING_CURSOR" end
    return create(branchPair, "none", "main_shaft", step - 1, mainOffset,
        "mine_main_cell", "main-" .. step, floor)
end

function Cursor.junction(branchPair, mainOffset, nextAction, floor)
    if type(nextAction) ~= "string" then return nil, "INVALID_MINING_CURSOR" end
    return create(branchPair, "none", "junction", 0, mainOffset, nextAction,
        "junction-" .. nextAction, floor)
end

function Cursor.branch(branchPair, side, phase, offset, mainOffset, nextAction, floor)
    if type(side) ~= "string" or type(phase) ~= "string"
        or not nonNegativeInteger(offset) then
        return nil, "INVALID_MINING_CURSOR"
    end
    return create(branchPair, side, phase, offset, mainOffset, nextAction,
        string.format("%s-%s-%d", side, phase, offset), floor)
end

-- Advance the durable cursor only after its named unit has completed.
function Cursor.transition(progress, event, updates)
    local PhaseMachine = require("src.mining.phase_machine")
    return PhaseMachine.transition(progress, event, Cursor, updates)
end

return Cursor
