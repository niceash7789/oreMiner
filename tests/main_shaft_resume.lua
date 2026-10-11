local Cursor = require("src.mining.cursor")
local Resume = require("src.mining.main_shaft_resume")

local start, code = Resume.start(assert(Cursor.mainShaft(3, 2, 6, 1)), 8, 3)
assert(start and start.branch == 3 and start.step == 2 and code == nil,
    "cursor offset must resume at that branch's next main-shaft cell")

start = assert(Resume.start(assert(Cursor.mainShaft(1, 1, 0, 1)), 8, 3))
assert(start.branch == 1 and start.step == 1,
    "the first cell cursor must resume at the first branch and step")

local invalid = assert(Cursor.mainShaft(3, 2, 6, 1))
invalid.mainOffset = 0
start, code = Resume.start(invalid, 8, 3)
assert(start == nil and code == "MAIN_SHAFT_CURSOR_OUT_OF_RANGE",
    "inconsistent main-shaft branch offset must be rejected")

start, code = Resume.start(assert(Cursor.mainShaft(1, 4, 0, 1)), 8, 3)
assert(start == nil and code == "MAIN_SHAFT_CURSOR_OUT_OF_RANGE",
    "a cell outside the configured spacing must be rejected")

print("main shaft resume checks passed")
