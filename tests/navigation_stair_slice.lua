local Motion = require("src.navigation.motion")
local Result = require("src.safety.result")
local StairSlice = require("src.navigation.stair_slice")
local FakeTurtle = require("tests.fake_turtle")

local function key(x, y, z)
    return table.concat({ x, y, z }, ",")
end

local function copyPose(pose)
    return { x = pose.x, y = pose.y, z = pose.z, facing = pose.facing }
end

local function assertPose(actual, expected, message)
    assert(actual and actual.x == expected.x and actual.y == expected.y
        and actual.z == expected.z and actual.facing == expected.facing, message)
end

local function target(pose, direction)
    if direction == "up" then return pose.x, pose.y + 1, pose.z end
    if direction == "down" then return pose.x, pose.y - 1, pose.z end
    local x, z = pose.x, pose.z
    if pose.facing == 0 then z = z - 1
    elseif pose.facing == 1 then x = x + 1
    elseif pose.facing == 2 then z = z + 1
    else x = x - 1 end
    return x, pose.y, z
end

local function worldHarness(startPose)
    local world = FakeTurtle.new(startPose)
    local pose = copyPose(startPose)
    local cleared = { [key(startPose.x, startPose.y, startPose.z)] = true }
    local clearCalls = 0

    local api = {
        forward = function()
            local x, y, z = target(pose, "forward")
            if not cleared[key(x, y, z)] then return false end
            return world:move("forward", true)
        end,
        back = function() return world:move("back", true) end,
        up = function() return world:move("up", true) end,
        down = function()
            local x, y, z = target(pose, "down")
            if not cleared[key(x, y, z)] then return false end
            return world:move("down", true)
        end,
        turnLeft = function() return world:turn("left", true) end,
        turnRight = function() return world:turn("right", true) end,
    }

    local harness = {}
    function harness.clear(direction)
        local x, y, z = target(pose, direction)
        cleared[key(x, y, z)] = true
        clearCalls = clearCalls + 1
        return Result.new(true, "CELL_CLEAR")
    end
    function harness.move(movement)
        local updated, outcome = Motion.move(pose, nil, movement, api)
        if outcome.ok then pose = updated end
        return updated, outcome
    end
    function harness.turn(direction)
        local updated, outcome = Motion.turn(pose, direction, api)
        if outcome.ok then pose = updated end
        return updated, outcome
    end
    function harness.pose() return copyPose(pose) end
    function harness.clearCount() return clearCalls end
    function harness.isClear(x, y, z) return cleared[key(x, y, z)] == true end
    return harness
end

local start = { x = 0, y = 0, z = 0, facing = 0 }
local invalidPose, invalid = StairSlice.descend(false)
assert(invalidPose == nil and not invalid.ok and invalid.code == "INVALID_STAIR_SLICE_OPTIONS")

local harness = worldHarness(start)
local descended, result = StairSlice.descend({
    pose = start,
    clear = harness.clear,
    move = harness.move,
    turn = harness.turn,
})
assert(result.ok and result.code == "STAIR_SLICE_COMPLETE")
assertPose(descended, { x = 0, y = -1, z = -1, facing = 0 },
    "one slice must advance one block forward/down and restore facing")
assertPose(harness.pose(), descended, "reported pose must match the simulated world")
for x = -1, 1 do
    for y = -1, 1 do
        assert(harness.isClear(x, y, -1), "slice must clear all nine passage cells")
    end
end
assert(harness.clearCount() == 9, "one solid slice should issue nine bounded clears")

local clearCountBeforeClimb = harness.clearCount()
local climbed, climbResult = StairSlice.climb({
    pose = descended,
    move = harness.move,
    turn = harness.turn,
})
assert(climbResult.ok and climbResult.code == "STAIR_SLICE_CLIMBED")
assertPose(climbed, start, "inverse climb must move up then back to the exact checkpoint")
assertPose(harness.pose(), start, "inverse climb world pose must match navigation pose")
assert(harness.clearCount() == clearCountBeforeClimb,
    "inverse climb must not excavate an already-cleared route")

local failureHarness = worldHarness(start)
local turns = 0
local failurePose, failure = StairSlice.descend({
    pose = start,
    clear = function(direction)
        if direction == "up" and turns == 1 then
            return Result.new(false, "UNBREAKABLE_BLOCK")
        end
        return failureHarness.clear(direction)
    end,
    move = failureHarness.move,
    turn = function(direction)
        turns = turns + 1
        return failureHarness.turn(direction)
    end,
})
assert(not failure.ok and failure.code == "UNBREAKABLE_BLOCK")
assertPose(failurePose, start,
    "a lateral clear failure must unwind to the last centre-bottom checkpoint")
assertPose(failureHarness.pose(), failurePose,
    "failure unwind must keep reported and physical pose aligned")

print("navigation stair slice checks passed")
