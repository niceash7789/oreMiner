local Cursor = require("src.mining.cursor")

local function transition(cursor, event, updates)
    local nextCursor, code = Cursor.transition(cursor, event, updates)
    assert(nextCursor, code)
    assert(Cursor.validate(nextCursor), "every transition must produce a valid cursor")
    return nextCursor
end

local source = assert(Cursor.mainShaft(2, 2, 1))
local mainNext = transition(source, "main_cell_complete", { offset = 2 })
assert(mainNext.phase == "main_shaft" and mainNext.offset == 2)
assert(source.phase == "main_shaft" and source.offset == 1,
    "transition must not mutate its input")

local junction = transition(mainNext, "main_segment_complete")
assert(junction.phase == "junction" and junction.nextAction == "turn_to_left_branch")
local outbound = transition(junction, "branch_started", { side = "left" })
assert(outbound.phase == "branch_outbound_lower" and outbound.side == "left")
local outboundNext = transition(outbound, "branch_cell_complete", { offset = 1 })
assert(outboundNext.offset == 1 and outboundNext.nextAction == "mine_branch_cell")
local turnaround = transition(outboundNext, "outbound_complete")
assert(turnaround.phase == "branch_turnaround" and turnaround.offset == 0)
local upper = transition(turnaround, "upper_return_started", { offset = 2 })
assert(upper.phase == "branch_upper_return" and upper.offset == 2)
local upperNext = transition(upper, "upper_cell_complete", { offset = 1 })
assert(upperNext.offset == 1)
local descend = transition(upperNext, "upper_return_complete")
assert(descend.phase == "branch_return_to_junction")
local restored = transition(descend, "junction_reached")
assert(restored.phase == "junction" and restored.nextAction == "restore_main_facing")
local main = transition(restored, "main_facing_restored")
assert(main.phase == "main_shaft" and main.side == "none")

local lower = transition(turnaround, "lower_return_started")
assert(lower.phase == "branch_lower_return")
local lowerJunction = transition(lower, "lower_return_complete")
assert(lowerJunction.phase == "junction" and lowerJunction.nextAction == "restore_main_facing")

local invalid, code = Cursor.transition(source, "outbound_complete")
assert(invalid == nil and code == "INVALID_PHASE_TRANSITION",
    "an event unavailable in the current phase must be rejected")
invalid, code = Cursor.transition(junction, "branch_started")
assert(invalid == nil and code == "INVALID_PHASE_TRANSITION",
    "a branch transition must identify its side")
invalid, code = Cursor.transition(source, "main_cell_complete", { side = "left" })
assert(invalid == nil and code == "INVALID_PHASE_TRANSITION",
    "transition updates must be restricted to cursor coordinates")

print("mining phase machine checks passed")
