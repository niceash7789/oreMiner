-- Translate a committed main-shaft cursor into the first floor-loop unit.
local Resume = {}

function Resume.start(cursor, branchCount, spacing)
    if type(cursor) ~= "table" or cursor.phase ~= "main_shaft"
        or cursor.nextAction ~= "mine_main_cell"
        or type(cursor.branchPair) ~= "number" or cursor.branchPair ~= math.floor(cursor.branchPair)
        or cursor.branchPair < 1 or type(branchCount) ~= "number"
        or branchCount ~= math.floor(branchCount) or branchCount < 1
        or cursor.branchPair > branchCount
        or type(cursor.offset) ~= "number" or cursor.offset ~= math.floor(cursor.offset)
        or cursor.offset < 0 or type(spacing) ~= "number"
        or spacing ~= math.floor(spacing) or spacing < 1 or cursor.offset >= spacing
        or cursor.mainOffset ~= (cursor.branchPair - 1) * spacing then
        return nil, "MAIN_SHAFT_CURSOR_OUT_OF_RANGE"
    end
    return { branch = cursor.branchPair, step = cursor.offset + 1 }
end

return Resume
