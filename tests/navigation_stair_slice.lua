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

local function worldHarness(startPose, failAt)
    local world = FakeTurtle.new(startPose)
    local pose = copyPose(startPose)
    local cleared = { [key(startPose.x, startPose.y, startPose.z)] = true }
    local clearCalls = 0
    local clearPoses = {}
    local physicalCalls = 0

    local function shouldFail()
        physicalCalls = physicalCalls + 1
        return physicalCalls == failAt
    end

    local api = {
        forward = function()
            if shouldFail() then return false end
            local x, y, z = target(pose, "forward")
            if not cleared[key(x, y, z)] then return false end
            return world:move("forward", true)
        end,
        back = function() if shouldFail() then return false end return world:move("back", true) end,
        up = function() if shouldFail() then return false end return world:move("up", true) end,
        down = function()
            if shouldFail() then return false end
            local x, y, z = target(pose, "down")
            if not cleared[key(x, y, z)] then return false end
            return world:move("down", true)
        end,
        turnLeft = function() if shouldFail() then return false end return world:turn("left", true) end,
        turnRight = function() if shouldFail() then return false end return world:turn("right", true) end,
    }

    local harness = {}
    function harness.clear(direction)
        clearPoses[#clearPoses + 1] = { pose = copyPose(pose), direction = direction }
        local x, y, z = target(pose, direction)
        cleared[key(x, y, z)] = true
        clearCalls = clearCalls + 1
        return Result.new(true, "CELL_CLEAR")
    end
    function harness.move(movement)
        local updated, outcome = Motion.move(pose, nil, movement, api)
        if outcome.ok then pose = updated end
        return updated, Result.new(outcome.ok, outcome.code, outcome.message, outcome)
    end
    function harness.turn(direction)
        local updated, outcome = Motion.turn(pose, direction, api)
        if outcome.ok then pose = updated end
        return updated, Result.new(outcome.ok, outcome.code, outcome.message, outcome)
    end
    function harness.pose() return copyPose(pose) end
    function harness.clearCount() return clearCalls end
    function harness.clearPoseTrace() return clearPoses end
    function harness.physicalCallCount() return physicalCalls end
    function harness.isClear(x, y, z) return cleared[key(x, y, z)] == true end
    return harness
end

local start = { x = 0, y = 0, z = 0, facing = 0 }
local invalidPose, invalid = StairSlice.descend(false)
assert(invalidPose == nil and not invalid.ok and invalid.code == "INVALID_STAIR_SLICE_OPTIONS")

local harness = worldHarness(start)
local torchCalls = 0
local descended, result = StairSlice.descend({
    pose = start,
    clear = harness.clear,
    move = harness.move,
    turn = harness.turn,
    placeOuterRightTorch = function(torchPose)
        torchCalls = torchCalls + 1
        assertPose(torchPose, { x = 0, y = 0, z = -1, facing = 0 },
            "stair torch callback runs at the cleared slice centre")
        return Result.new(true, "TORCH_PLACED")
    end,
})
assert(result.ok and result.code == "STAIR_SLICE_COMPLETE")
assertPose(descended, { x = 0, y = -1, z = -1, facing = 0 },
    "one slice must advance one block forward/down and restore facing")
assertPose(harness.pose(), descended, "reported pose must match the simulated world")
for x = -1, 1 do
    for y = -1, 2 do
        assert(harness.isClear(x, y, -1), "slice must clear all twelve passage cells")
    end
end
assert(harness.clearCount() == 12, "one solid slice should issue twelve bounded clears")
assert(torchCalls == 1, "optional torch callback runs once after passage clearing")

-- Each centre and lateral sweep sub-phase must issue its clears from the
-- expected pose. The next column may start only after the prior column has
-- unwound to centre-bottom/facing.
local function assertClearTrace(trace, origin, forwardX, forwardZ, rightX, rightZ)
    local middle = { x = origin.x + forwardX, y = origin.y, z = origin.z + forwardZ, facing = origin.facing }
    local left = { x = middle.x - rightX, y = middle.y, z = middle.z - rightZ, facing = (origin.facing + 3) % 4 }
    local right = { x = middle.x + rightX, y = middle.y, z = middle.z + rightZ, facing = (origin.facing + 1) % 4 }
    local centreLeft = { x = middle.x, y = middle.y, z = middle.z, facing = left.facing }
    local centreRight = { x = middle.x, y = middle.y, z = middle.z, facing = right.facing }
    local expected = {
        { origin, "forward" },
        { middle, "up" },
        { { x = middle.x, y = middle.y + 1, z = middle.z, facing = middle.facing }, "up" },
        { middle, "down" },
        { centreLeft, "forward" }, { left, "up" },
        { { x = left.x, y = left.y + 1, z = left.z, facing = left.facing }, "up" },
        { left, "down" },
        { centreRight, "forward" }, { right, "up" },
        { { x = right.x, y = right.y + 1, z = right.z, facing = right.facing }, "up" },
        { right, "down" },
    }
    assert(#trace == #expected, "slice clear trace must contain three complete columns")
    for index, entry in ipairs(expected) do
        assertPose(trace[index].pose, entry[1], "clear sub-phase pose " .. index)
        assert(trace[index].direction == entry[2], "clear sub-phase direction " .. index)
    end
end

assertClearTrace(harness.clearPoseTrace(), start, 0, -1, 1, 0)

-- Slice geometry is route-frame relative; verify the same target cells and
-- centre-bottom postcondition for every possible outward facing.
for facing = 1, 3 do
    local rotatedStart = { x = 7, y = -3, z = 11, facing = facing }
    local rotatedHarness = worldHarness(rotatedStart)
    local rotatedEnd, rotatedResult = StairSlice.descend({
        pose = rotatedStart,
        clear = rotatedHarness.clear,
        move = rotatedHarness.move,
        turn = rotatedHarness.turn,
    })
    local dx, dz = 0, 0
    if facing == 0 then dz = -1
    elseif facing == 1 then dx = 1
    elseif facing == 2 then dz = 1
    else dx = -1 end
    assert(rotatedResult.ok and rotatedResult.code == "STAIR_SLICE_COMPLETE",
        "slice should complete facing " .. facing)
    assertPose(rotatedEnd, {
        x = rotatedStart.x + dx, y = rotatedStart.y - 1,
        z = rotatedStart.z + dz, facing = facing,
    }, "slice must advance forward/down and preserve facing " .. facing)
    assertPose(rotatedHarness.pose(), rotatedEnd,
        "simulated world must match returned pose facing " .. facing)
    local rightX, rightZ
    if facing == 0 then rightX, rightZ = 1, 0
    elseif facing == 1 then rightX, rightZ = 0, 1
    elseif facing == 2 then rightX, rightZ = -1, 0
    else rightX, rightZ = 0, -1 end
    for lateral = -1, 1 do
        for height = -1, 2 do
            assert(rotatedHarness.isClear(
                rotatedStart.x + dx + lateral * rightX,
                rotatedStart.y + height,
                rotatedStart.z + dz + lateral * rightZ),
                "slice must clear the route-relative 3x4 cells facing " .. facing)
        end
    end
    assert(rotatedHarness.clearCount() == 12,
        "slice must clear exactly twelve target cells facing " .. facing)
    assertClearTrace(rotatedHarness.clearPoseTrace(), rotatedStart, dx, dz, rightX, rightZ)
end

local torchFailureHarness = worldHarness(start)
local torchFailurePose, torchFailure = StairSlice.descend({
    pose = start,
    clear = torchFailureHarness.clear,
    move = torchFailureHarness.move,
    turn = torchFailureHarness.turn,
    placeOuterRightTorch = function() return Result.new(false, "NO_TORCHES") end,
})
assert(not torchFailure.ok and torchFailure.code == "NO_TORCHES")
assertPose(torchFailurePose, { x = 0, y = 0, z = 0, facing = 0 },
    "torch failure unwinds to the previous committed centre before stopping")

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

-- Fault each physical move/turn position observed in a successful slice. A
-- failed API result must never advance either the simulated world or pose,
-- including when the slice is attempting its bounded local unwind.
local baseline = worldHarness(start)
local _, baselineOutcome = StairSlice.descend({
    pose = start, clear = baseline.clear, move = baseline.move, turn = baseline.turn,
})
assert(baselineOutcome.ok)
local physicalBoundaries = baseline.physicalCallCount()
for failAt = 1, physicalBoundaries do
    local faulted = worldHarness(start, failAt)
    local failedPose, failedOutcome = StairSlice.descend({
        pose = start, clear = faulted.clear, move = faulted.move, turn = faulted.turn,
    })
    assert(not failedOutcome.ok, "injected physical failure must stop the slice")
    assertPose(failedPose, faulted.pose(),
        "reported pose must match world after physical failure at call " .. failAt)
end

print("navigation stair slice checks passed")
