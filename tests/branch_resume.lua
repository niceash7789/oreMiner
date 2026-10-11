local Resume = require("src.mining.branch_resume")
local Cursor = require("src.mining.cursor")

local cursor = assert(Cursor.branch(2, "right", "branch_outbound_lower", 3,
    6, "mine_branch_cell", 1))
local start = assert(Resume.start(cursor, 4, 3, 30))
assert(start.phase == "branch_outbound_lower" and start.branch == 2
    and start.side == "right" and start.distance == 3,
    "branch resume must preserve pair, side, and committed outbound distance")

local invalid, code = Resume.start(cursor, 1, 3, 30)
assert(invalid == nil and code == "BRANCH_CURSOR_OUT_OF_RANGE")
invalid, code = Resume.start(cursor, 4, 3, 3)
assert(invalid == nil and code == "BRANCH_CURSOR_OUT_OF_RANGE",
    "a cursor at the configured endpoint belongs to turnaround, not outbound mining")

local returnCases = {
    { "branch_turnaround", 30, "prepare_branch_return" },
    { "branch_upper_return", 0, "scan_and_return_branch_cell" },
    { "branch_upper_return", 30, "scan_and_return_branch_cell" },
    { "branch_lower_return", 12, "return_branch_cell" },
    { "branch_return_to_junction", 0, "descend_to_junction" },
}
for _, case in ipairs(returnCases) do
    cursor = assert(Cursor.branch(2, "right", case[1], case[2], 6, case[3], 1))
    start = assert(Resume.start(cursor, 4, 3, 30))
    assert(start.phase == case[1] and start.branch == 2
        and start.side == "right" and start.distance == case[2]
        and start.action == case[3], "branch return cursor should map without changing its boundary")
end

cursor = assert(Cursor.branch(2, "right", "branch_turnaround", 29, 6,
    "prepare_branch_return", 1))
invalid, code = Resume.start(cursor, 4, 3, 30)
assert(invalid == nil and code == "BRANCH_CURSOR_OUT_OF_RANGE",
    "turnaround is valid only at the configured endpoint")

cursor = assert(Cursor.branch(2, "right", "branch_return_to_junction", 1, 6,
    "descend_to_junction", 1))
invalid, code = Resume.start(cursor, 4, 3, 30)
assert(invalid == nil and code == "BRANCH_CURSOR_OUT_OF_RANGE",
    "junction descent is valid only at offset zero")

print("branch resume checks passed")
