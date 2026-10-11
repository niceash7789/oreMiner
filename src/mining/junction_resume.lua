-- Map a committed junction cursor to the next floor-loop position.
local Resume = {}

function Resume.start(cursor, branchCount, spacing)
    if type(cursor) ~= "table" or cursor.phase ~= "junction"
        or type(cursor.floor) ~= "number" or cursor.floor < 1
        or type(cursor.branchPair) ~= "number" or cursor.branchPair ~= math.floor(cursor.branchPair)
        or cursor.branchPair < 1 or type(branchCount) ~= "number"
        or branchCount ~= math.floor(branchCount) or branchCount < 1
        or cursor.branchPair > branchCount
        or type(spacing) ~= "number" or spacing ~= math.floor(spacing) or spacing < 1
        or type(cursor.mainOffset) ~= "number" or cursor.mainOffset ~= cursor.branchPair * spacing
        or cursor.offset ~= 0 or cursor.side ~= "none"
        or (cursor.nextAction ~= "turn_to_left_branch"
            and cursor.nextAction ~= "restore_main_facing") then
        return nil, "JUNCTION_CURSOR_OUT_OF_RANGE"
    end
    if cursor.nextAction == "turn_to_left_branch" then
        return { branch = cursor.branchPair, step = spacing + 1, action = cursor.nextAction }
    end
    return { branch = cursor.branchPair + 1, step = 1, action = cursor.nextAction }
end

return Resume
