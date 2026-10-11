local Resume = require("src.mining.junction_resume")
local Cursor = require("src.mining.cursor")

local start = assert(Resume.start(
    assert(Cursor.junction(2, 6, "turn_to_left_branch", 1)), 4, 3))
assert(start.branch == 2 and start.step == 4 and start.action == "turn_to_left_branch",
    "left-branch junction cursor must skip completed main-shaft cells")

start = assert(Resume.start(
    assert(Cursor.junction(2, 6, "restore_main_facing", 1)), 4, 3))
assert(start.branch == 3 and start.step == 1 and start.action == "restore_main_facing",
    "restored-facing cursor must continue at the next shaft pair")
start = assert(Resume.start(
    assert(Cursor.junction(2, 6, "turn_to_left_branch", 1, "left")), 4, 3))
assert(start.mainSide == "left" and start.branch == 2,
    "junction resume must preserve the opposite main-shaft side")

local invalid, code = Resume.start(
    assert(Cursor.junction(4, 12, "turn_to_left_branch", 1)), 3, 3)
assert(invalid == nil and code == "JUNCTION_CURSOR_OUT_OF_RANGE")
invalid, code = Resume.start(
    assert(Cursor.junction(1, 0, "turn_to_left_branch", 1)), 3, 0)
assert(invalid == nil and code == "JUNCTION_CURSOR_OUT_OF_RANGE")

print("junction resume checks passed")
