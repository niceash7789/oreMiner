-- Durable logical cursor for the next bounded route or mining unit.
local Cursor = {}

local PHASE_ACTIONS = {
    surface_entry = { enter_surface = true },
    stairs = {
        cross_landing = true,
        descend_stair_slice = true,
        prepare_landing = true,
    },
    main_side_start = { turn_into_main = true },
    main_shaft = { mine_main_cell = true },
    main_side_return = { return_to_landing = true },
    junction = { turn_to_left_branch = true, restore_main_facing = true },
    branch_outbound_lower = { mine_branch_cell = true },
    branch_turnaround = { prepare_branch_return = true },
    branch_upper_return = { scan_and_return_branch_cell = true },
    branch_lower_return = { return_branch_cell = true },
    branch_return_to_junction = { descend_to_junction = true },
    floor_complete = { advance_floor = true },
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

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local StairGeometry = require("src.core.stair_geometry")

-- Attach the durable frame and configured bounds at the exact committed pose
-- from which this next cursor will run. The logical cursor itself remains the
-- compact route position; these fields make its work unit independently clear.
function Cursor.withWorkUnit(progress, origin, config)
    if not Cursor.validate(progress) or type(origin) ~= "table"
        or not integer(origin.x) or not integer(origin.y) or not integer(origin.z)
        or not integer(origin.facing) or origin.facing < 0 or origin.facing > 3
        or type(config) ~= "table" or not integer(config.branch_length)
        or not integer(config.num_branches) or not integer(config.spacing)
        or (config.floor_count ~= nil and not integer(config.floor_count))
        or (config.stair_steps_per_floor ~= nil and not integer(config.stair_steps_per_floor))
        or (config.first_floor_depth_offset ~= nil
            and (not integer(config.first_floor_depth_offset)
                or config.first_floor_depth_offset < 0)) then
        return nil, "INVALID_WORK_UNIT"
    end
    local floorCount = config.floor_count or 1
    local stairSteps = StairGeometry.stepsForFloor(
        config.stair_steps_per_floor or 8,
        config.first_floor_depth_offset or 0,
        math.max(progress.floor, 1))
    if not stairSteps then return nil, "INVALID_WORK_UNIT" end
    local outboundFrame = origin.facing
    if progress.phase == "branch_upper_return" or progress.phase == "branch_lower_return"
        or progress.phase == "branch_return_to_junction" then
        outboundFrame = (origin.facing + 2) % 4
    end
    local result = copy(progress)
    result.origin = copy(origin)
    result.outboundFrame = outboundFrame
    result.bounds = {
        floorFirst = progress.floor,
        floorLast = floorCount,
        branchPairFirst = 1,
        branchPairLast = config.num_branches,
        offsetFirst = 0,
        offsetLast = progress.phase == "main_shaft" or progress.phase == "junction"
            and config.spacing or config.branch_length,
        mainOffsetFirst = 0,
        -- Coordinator offsets are one-based at a junction boundary, so the
        -- last pair may be represented by num_branches * spacing.
        mainOffsetLast = config.num_branches * config.spacing,
        stairStepFirst = 1,
        stairStepLast = stairSteps + 1, -- step+1 is the durable landing-preparation cursor
    }
    if progress.phase == "main_shaft" or progress.phase == "junction" then
        result.bounds.offsetLast = config.spacing
    elseif progress.phase == "surface_entry" or progress.phase == "stairs" then
        result.bounds.offsetLast = stairSteps + 1
    end
    result.completionStatus = "pending"
    return result
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
        or (progress.mainSide ~= nil and progress.mainSide ~= "left"
            and progress.mainSide ~= "right")
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
    if progress.phase == "main_side_start" or progress.phase == "main_side_return"
        or progress.phase == "main_shaft" or progress.phase == "junction" then
        return progress.side == "none"
    end
    if progress.phase == "floor_complete" then
        return progress.side == "none" and progress.floor >= 1
    end
    return progress.side == "left" or progress.side == "right"
end

local function create(branchPair, side, phase, offset, mainOffset, nextAction, suffix, floor, mainSide)
    if not integer(branchPair) or branchPair < 1
        or type(side) ~= "string"
        or type(phase) ~= "string"
        or not nonNegativeInteger(offset)
        or not nonNegativeInteger(mainOffset)
        or type(nextAction) ~= "string"
        or type(suffix) ~= "string"
        or (floor ~= nil and not nonNegativeInteger(floor))
        or (mainSide ~= nil and mainSide ~= "left" and mainSide ~= "right") then
        return nil, "INVALID_MINING_CURSOR"
    end
    local unitSuffix = mainSide == "left" and "left-main-" .. suffix or suffix
    local progress = {
        workDomain = "floor",
        workUnitId = floor and floor > 0
            and string.format("floor-%d-pair-%d-%s", floor, branchPair, unitSuffix)
            or string.format("surface-pair-%d-%s", branchPair, unitSuffix),
        floor = floor or 0,
        stairSegment = floor and math.max(0, floor - 1) or 0,
        stairStep = 0,
        branchPair = branchPair,
        side = side,
        mainSide = mainSide or "right",
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

function Cursor.floorComplete(floor)
    if not integer(floor) or floor < 1 then return nil, "INVALID_MINING_CURSOR" end
    return create(1, "none", "floor_complete", 0, 0, "advance_floor", "complete", floor)
end

function Cursor.mainSideStart(floor, mainSide)
    if not integer(floor) or floor < 1 then return nil, "INVALID_MINING_CURSOR" end
    return create(1, "none", "main_side_start", 0, 0,
        "turn_into_main", "start", floor, mainSide)
end

function Cursor.mainSideReturn(floor, mainSide, branchCount, mainOffset)
    if not integer(floor) or floor < 1 or not integer(branchCount)
        or branchCount < 1 or not nonNegativeInteger(mainOffset) then
        return nil, "INVALID_MINING_CURSOR"
    end
    return create(branchCount, "none", "main_side_return", 0, mainOffset,
        "return_to_landing", "return", floor, mainSide)
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

function Cursor.mainShaft(branchPair, step, mainOffset, floor, mainSide)
    if not integer(step) or step < 1 then return nil, "INVALID_MINING_CURSOR" end
    return create(branchPair, "none", "main_shaft", step - 1, mainOffset,
        "mine_main_cell", "main-" .. step, floor, mainSide)
end

function Cursor.junction(branchPair, mainOffset, nextAction, floor, mainSide)
    if type(nextAction) ~= "string" then return nil, "INVALID_MINING_CURSOR" end
    return create(branchPair, "none", "junction", 0, mainOffset, nextAction,
        "junction-" .. nextAction, floor, mainSide)
end

function Cursor.branch(branchPair, side, phase, offset, mainOffset, nextAction, floor, mainSide)
    if type(side) ~= "string" or type(phase) ~= "string"
        or not nonNegativeInteger(offset) then
        return nil, "INVALID_MINING_CURSOR"
    end
    return create(branchPair, side, phase, offset, mainOffset, nextAction,
        string.format("%s-%s-%d", side, phase, offset), floor, mainSide)
end

-- Advance the durable cursor only after its named unit has completed.
function Cursor.transition(progress, event, updates)
    local PhaseMachine = require("src.mining.phase_machine")
    return PhaseMachine.transition(progress, event, Cursor, updates)
end

return Cursor
