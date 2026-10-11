local Cursor = require("src.mining.cursor")

local initial = assert(Cursor.initial())
assert(initial.workUnitId == "surface-pair-1-main-1")
assert(initial.floor == 0 and initial.branchPair == 1 and initial.offset == 0)
assert(initial.phase == "main_shaft" and initial.nextAction == "mine_main_cell")
assert(Cursor.validate(initial), "initial cursor should be valid")
local completed = assert(Cursor.floorComplete(2))
assert(Cursor.validate(completed) and completed.floor == 2
    and completed.phase == "floor_complete" and completed.nextAction == "advance_floor",
    "floor completion requires a valid durable cursor")

local entry = assert(Cursor.stairs(1, 0, "enter_surface"))
assert(entry.workDomain == "shaft" and entry.floor == 1
    and entry.stairSegment == 0 and entry.phase == "surface_entry")
assert(Cursor.validate(entry), "surface entry cursor should be valid")
local stair = assert(Cursor.stairs(1, 5, "descend_stair_slice"))
assert(stair.workUnitId == "floor-1-stairs-5-descend_stair_slice")
assert(stair.stairStep == 5 and stair.offset == 5 and stair.phase == "stairs")
assert(Cursor.validate(stair), "stair slice cursor should be valid")
local offsetFrame = assert(Cursor.withWorkUnit(stair,
    { x = 0, y = -4, z = -8, facing = 0 }, {
        branch_length = 30, num_branches = 2, spacing = 3,
        floor_count = 2, stair_steps_per_floor = 4,
        first_floor_depth_offset = 3,
    }))
assert(offsetFrame.bounds.stairStepLast == 8 and offsetFrame.bounds.offsetLast == 8,
    "first-floor cursor bounds must include the deeper descent and landing cursor")
local laterFrame = assert(Cursor.withWorkUnit(assert(Cursor.stairs(2, 0, "cross_landing")),
    { x = 0, y = -7, z = -12, facing = 0 }, {
        branch_length = 30, num_branches = 2, spacing = 3,
        floor_count = 2, stair_steps_per_floor = 4,
        first_floor_depth_offset = 3,
    }))
assert(laterFrame.bounds.stairStepLast == 5,
    "later-floor cursor bounds must use the ordinary interval")
local landing = assert(Cursor.stairs(1, 8, "prepare_landing"))
assert(Cursor.validate(landing), "landing preparation cursor should be valid")
local crossing = assert(Cursor.stairs(2, 0, "cross_landing"))
assert(crossing.floor == 2 and crossing.stairSegment == 1 and Cursor.validate(crossing),
    "later-floor cursor should persist its landing crossing")
assert(not Cursor.stairs(0, 0, "enter_surface"), "route cursors require a positive floor")
assert(not Cursor.stairs(1, 9, "unknown_action"), "route cursors reject unknown actions")

local main = assert(Cursor.mainShaft(3, 2, 6))
assert(main.branchPair == 3 and main.offset == 1 and main.mainOffset == 6)
assert(main.side == "none" and main.nextAction == "mine_main_cell")
local floorTwoMain = assert(Cursor.mainShaft(3, 2, 6, 2))
assert(floorTwoMain.floor == 2 and floorTwoMain.workUnitId:find("floor-2-", 1, true),
    "mining work-unit IDs should remain distinct across floors")
local leftMain = assert(Cursor.mainShaft(3, 2, 6, 2, "left"))
assert(leftMain.mainSide == "left" and leftMain.workUnitId ~= floorTwoMain.workUnitId,
    "mirrored main-shaft work units must have distinct durable IDs")
assert(Cursor.validate(assert(Cursor.mainSideStart(2, "left"))))
assert(Cursor.validate(assert(Cursor.mainSideReturn(2, "left", 3, 9))))

local outbound = assert(Cursor.branch(3, "left", "branch_outbound_lower", 4, 9,
    "mine_branch_cell"))
assert(outbound.workUnitId == "surface-pair-3-left-branch_outbound_lower-4")
assert(Cursor.validate(outbound), "branch cursor should be valid")

local upperReturn = assert(Cursor.branch(3, "right", "branch_upper_return", 7, 9,
    "scan_and_return_branch_cell"))
assert(Cursor.validate(upperReturn), "upper-return cursor should be valid")

local invalid, invalidCode = Cursor.branch(3, "none", "branch_outbound_lower", 0, 9,
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
