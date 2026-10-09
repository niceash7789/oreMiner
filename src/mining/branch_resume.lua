-- Validate a saved branch cursor and map it to the exact executor boundary.
local Resume = {}

local ACTIONS = {
    branch_outbound_lower = "mine_branch_cell",
    branch_turnaround = "prepare_branch_return",
    branch_upper_return = "scan_and_return_branch_cell",
    branch_lower_return = "return_branch_cell",
    branch_return_to_junction = "descend_to_junction",
}

function Resume.start(cursor, branchCount, spacing, branchLength)
    local phase = type(cursor) == "table" and cursor.phase or nil
    local action = ACTIONS[phase]
    local validLength = type(branchLength) == "number" and branchLength == math.floor(branchLength)
    local maximumOffset = validLength and phase == "branch_outbound_lower"
        and branchLength - 1 or branchLength
    if type(cursor) ~= "table" or not action or cursor.nextAction ~= action
        or (cursor.side ~= "left" and cursor.side ~= "right")
        or type(cursor.floor) ~= "number" or cursor.floor ~= math.floor(cursor.floor)
        or cursor.floor < 1
        or type(cursor.branchPair) ~= "number" or cursor.branchPair ~= math.floor(cursor.branchPair)
        or type(branchCount) ~= "number" or branchCount ~= math.floor(branchCount)
        or cursor.branchPair > branchCount or cursor.branchPair < 1
        or cursor.mainOffset ~= cursor.branchPair
        or type(spacing) ~= "number" or spacing ~= math.floor(spacing) or spacing < 1
        or not validLength
        or type(cursor.offset) ~= "number" or cursor.offset ~= math.floor(cursor.offset)
        or cursor.offset < 0 or cursor.offset > maximumOffset
        or (phase == "branch_return_to_junction" and cursor.offset ~= 0)
        or (phase == "branch_turnaround" and cursor.offset ~= branchLength) then
        return nil, "BRANCH_CURSOR_OUT_OF_RANGE"
    end
    return {
        phase = cursor.phase,
        branch = cursor.branchPair,
        side = cursor.side,
        distance = cursor.offset,
        action = cursor.nextAction,
    }
end

return Resume
