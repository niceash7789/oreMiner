-- Pure logical phase transitions for the active single-floor mining baseline.
-- A phase/action pair always describes the next unit that has not started.
local PhaseMachine = {}

local TRANSITIONS = {
    main_shaft = {
        main_cell_complete = { phase = "main_shaft", nextAction = "mine_main_cell" },
        main_segment_complete = { phase = "junction", nextAction = "turn_to_left_branch" },
    },
    junction = {
        branch_started = { phase = "branch_outbound_lower", nextAction = "mine_branch_cell" },
        main_facing_restored = { phase = "main_shaft", nextAction = "mine_main_cell" },
    },
    branch_outbound_lower = {
        branch_cell_complete = { phase = "branch_outbound_lower", nextAction = "mine_branch_cell" },
        outbound_complete = { phase = "branch_turnaround", nextAction = "prepare_branch_return" },
    },
    branch_turnaround = {
        upper_return_started = { phase = "branch_upper_return", nextAction = "scan_and_return_branch_cell" },
        lower_return_started = { phase = "branch_lower_return", nextAction = "return_branch_cell" },
    },
    branch_upper_return = {
        upper_cell_complete = { phase = "branch_upper_return", nextAction = "scan_and_return_branch_cell" },
        upper_return_complete = { phase = "branch_return_to_junction", nextAction = "descend_to_junction" },
    },
    branch_lower_return = {
        lower_cell_complete = { phase = "branch_lower_return", nextAction = "return_branch_cell" },
        lower_return_complete = { phase = "junction", nextAction = "restore_main_facing" },
    },
    branch_return_to_junction = {
        junction_reached = { phase = "junction", nextAction = "restore_main_facing" },
    },
}

local function copyProgress(progress)
    local copy = {}
    for key, value in pairs(progress) do copy[key] = value end
    return copy
end

function PhaseMachine.transition(progress, event, Cursor, updates)
    if type(progress) ~= "table" or type(event) ~= "string"
        or type(Cursor) ~= "table" or type(Cursor.validate) ~= "function"
        or not Cursor.validate(progress) then
        return nil, "INVALID_MINING_CURSOR"
    end

    local phaseTransitions = TRANSITIONS[progress.phase]
    local target = phaseTransitions and phaseTransitions[event]
    if not target then return nil, "INVALID_PHASE_TRANSITION" end

    if updates ~= nil and type(updates) ~= "table" then
        return nil, "INVALID_PHASE_TRANSITION"
    end
    local nextProgress = copyProgress(progress)
    nextProgress.phase = target.phase
    nextProgress.nextAction = target.nextAction
    if target.phase ~= progress.phase then
        nextProgress.offset = 0
    end
    if target.phase == "main_shaft" or target.phase == "junction" then
        nextProgress.side = "none"
    elseif progress.side == "none" and updates and updates.side then
        nextProgress.side = updates.side
    end
    if updates then
        for key, value in pairs(updates) do
            if key ~= "side" and key ~= "offset" and key ~= "mainOffset" then
                return nil, "INVALID_PHASE_TRANSITION"
            end
            nextProgress[key] = value
        end
    end
    nextProgress.workUnitId = string.format("surface-pair-%d-%s-%s-%d",
        nextProgress.branchPair, nextProgress.side, nextProgress.phase, nextProgress.offset)
    local valid = Cursor.validate(nextProgress)
    if not valid then return nil, "INVALID_PHASE_TRANSITION" end
    return nextProgress
end

return PhaseMachine
