local Pose = require("src.navigation.pose")
local Turn = require("src.navigation.turn")
local FakeTurtle = require("tests.fake_turtle")

local function expectSequence(from, target)
    local start = assert(Pose.new(2, 3, 4, from))
    local world = FakeTurtle.new(start)
    local calls = {}
    local updated, result = Turn.face(start, target, function(direction)
        calls[#calls + 1] = direction
        local apiResult = world:turn(direction, true)
        local nextPose, status = Pose.afterTurn(start, direction, apiResult)
        start = nextPose
        return nextPose, status
    end)
    local delta = (target - from) % 4
    local expected = delta == 0 and {} or delta == 1 and { "right" }
        or delta == 2 and { "right", "right" } or { "left" }
    assert(result.ok and updated.facing == target, "face reaches requested facing")
    assert(result.turns == #expected, "face reports shortest turn count")
    assert(#calls == #expected, "face issues shortest turn sequence")
    for index, direction in ipairs(expected) do
        assert(calls[index] == direction, "face chooses correct direction at step " .. index)
    end
    assert(world.pose.facing == target, "fake turtle records requested facing")
end

for from = 0, 3 do
    for target = 0, 3 do
        expectSequence(from, target)
    end
end

local initial = assert(Pose.new(0, 0, 0, 0))
local physical = FakeTurtle.new(initial)
local calls = 0
local partial, failed = Turn.face(initial, 2, function(direction)
    calls = calls + 1
    local apiResult = physical:turn(direction, calls == 1)
    local nextPose, status = Pose.afterTurn(initial, direction, apiResult)
    if apiResult == true then initial = nextPose end
    return nextPose, status
end)
assert(not failed.ok and failed.code == "TURN_FAILED", "face propagates checked turn failure")
assert(calls == 2, "face stops after a failed turn")
assert(partial.facing == 1 and physical.pose.facing == 1, "successful first turn is recorded")

local unchanged, invalid = Turn.face(partial, 4, function() error("invalid target must not turn") end)
assert(not invalid.ok and invalid.code == "INVALID_FACING", "face rejects invalid target")
assert(unchanged.facing == 1, "invalid target preserves pose")

print("navigation face checks passed")
