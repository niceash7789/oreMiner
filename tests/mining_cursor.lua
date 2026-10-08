local Cursor = require("src.mining.cursor")

local initial = assert(Cursor.initial())
assert(initial.workUnitId == "surface-pair-1-main-1")
assert(initial.floor == 0 and initial.branchPair == 1 and initial.offset == 0)
assert(initial.phase == "main_shaft" and initial.nextAction == "mine_main_cell")
assert(Cursor.validate(initial), "initial cursor should be valid")

local main = assert(Cursor.mainShaft(3, 2, 2))
assert(main.branchPair == 3 and main.offset == 1 and main.mainOffset == 2)
assert(main.side == "none" and main.nextAction == "mine_main_cell")

local outbound = assert(Cursor.branch(3, "left", "branch_outbound_lower", 4, 3,
    "mine_branch_cell"))
assert(outbound.workUnitId == "surface-pair-3-left-branch_outbound_lower-4")
assert(Cursor.validate(outbound), "branch cursor should be valid")

local upperReturn = assert(Cursor.branch(3, "right", "branch_upper_return", 7, 3,
    "scan_and_return_branch_cell"))
assert(Cursor.validate(upperReturn), "upper-return cursor should be valid")

local invalid, invalidCode = Cursor.branch(3, "none", "branch_outbound_lower", 0, 3,
    "mine_branch_cell")
assert(invalid == nil and invalidCode == "INVALID_MINING_CURSOR",
    "branch phases require a left or right side")
assert(not Cursor.validate({}), "incomplete cursor should be invalid")
assert(not Cursor.validate({
    workDomain = "floor",
    workUnitId = "surface-pair-1-main-1",
    floor = 0,
    stairSegment = 0,
    stairStep = 0,
    branchPair = 1,
    side = "none",
    phase = "main_shaft",
    offset = 0,
    mainOffset = 0,
    nextAction = "already_done",
}), "phase and next action must agree")

print("mining cursor checks passed")
