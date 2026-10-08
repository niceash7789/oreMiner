-- Run from the project root with a Lua interpreter or CC:Tweaked computer:
-- lua tests/navigation_pose.lua
local Pose = require("src.navigation.pose")
local FakeTurtle = require("tests.fake_turtle")
local Turn = require("src.navigation.turn")

local function assertPose(actual, expected, label)
    assert(actual ~= nil, label .. ": pose was nil")
    assert(actual.x == expected.x, label .. ": x changed unexpectedly")
    assert(actual.y == expected.y, label .. ": y changed unexpectedly")
    assert(actual.z == expected.z, label .. ": z changed unexpectedly")
    assert(actual.facing == expected.facing, label .. ": facing changed unexpectedly")
end

local function checkFailure(apiResult, label)
    local start = assert(Pose.new(0, 0, 0, 0))
    local expectedStart = { x = 0, y = 0, z = 0, facing = 0 }
    local world = FakeTurtle.new(start)
    local returnedResult = world:move("forward", apiResult)
    local tracked, status = Pose.afterMove(start, "forward", returnedResult)

    assert(status.ok == false, label .. ": non-true result must be a failure")
    assert(status.code == "MOVE_FAILED", label .. ": failure should use MOVE_FAILED")
    assertPose(world.pose, expectedStart, label .. ": simulated turtle")
    assertPose(tracked, expectedStart, label .. ": tracked pose")
end

local start = assert(Pose.new(0, 0, 0, 0))
local expectedStart = { x = 0, y = 0, z = 0, facing = 0 }

-- Every horizontal direction is checked in every facing; vertical movement is
-- independent of facing. Compare the pure transform with the fake turtle.
local expectedHorizontal = {
    forward = {
        { x = 0, y = 0, z = -1 },
        { x = 1, y = 0, z = 0 },
        { x = 0, y = 0, z = 1 },
        { x = -1, y = 0, z = 0 },
    },
    back = {
        { x = 0, y = 0, z = 1 },
        { x = -1, y = 0, z = 0 },
        { x = 0, y = 0, z = -1 },
        { x = 1, y = 0, z = 0 },
    },
}

for facing = 0, 3 do
    for movement, expectedByFacing in pairs(expectedHorizontal) do
        local pose = assert(Pose.new(5, 7, 11, facing))
        local original = { x = pose.x, y = pose.y, z = pose.z, facing = pose.facing }
        local expectedDelta = expectedByFacing[facing + 1]
        local expected = {
            x = original.x + expectedDelta.x,
            y = original.y + expectedDelta.y,
            z = original.z + expectedDelta.z,
            facing = facing,
        }
        local world = FakeTurtle.new(pose)
        local apiResult = world:move(movement, true)
        local tracked, result = Pose.afterMove(pose, movement, apiResult)

        assert(result.ok == true, movement .. " facing " .. facing .. " should succeed")
        assertPose(world.pose, expected, movement .. " facing " .. facing .. " simulated turtle")
        assertPose(tracked, expected, movement .. " facing " .. facing .. " tracked pose")
        assertPose(pose, original, movement .. " facing " .. facing .. " original input")
    end

    for _, vertical in ipairs({
        { movement = "up", delta = 1 },
        { movement = "down", delta = -1 },
    }) do
        local pose = assert(Pose.new(5, 7, 11, facing))
        local world = FakeTurtle.new(pose)
        local apiResult = world:move(vertical.movement, true)
        local tracked, result = Pose.afterMove(pose, vertical.movement, apiResult)
        local expected = { x = 5, y = 7 + vertical.delta, z = 11, facing = facing }

        assert(result.ok == true, vertical.movement .. " facing " .. facing .. " should succeed")
        assertPose(world.pose, expected, vertical.movement .. " facing " .. facing .. " simulated turtle")
        assertPose(tracked, expected, vertical.movement .. " facing " .. facing .. " tracked pose")
        assertPose(pose, { x = 5, y = 7, z = 11, facing = facing }, vertical.movement .. " input unchanged")
    end
end

-- A failed, absent, or malformed API result must leave both poses unchanged.
checkFailure(false, "false result")
checkFailure(nil, "nil result")
checkFailure("unexpected truthy result", "truthy non-boolean result")

print("navigation pose movement checks passed")

local function checkTurn(direction, apiResult, expectedFacing, expectedCode)
    local startPose = assert(Pose.new(0, 0, 0, 2))
    local world = FakeTurtle.new(startPose)
    local api = {
        turnLeft = function() return world:turn("left", apiResult) end,
        turnRight = function() return world:turn("right", apiResult) end,
    }
    local tracked, status = Turn.run(startPose, direction, api)
    assert(status.code == expectedCode, direction .. " turn status")
    assert(status.ok == (apiResult == true), direction .. " turn result")
    assert(tracked.facing == expectedFacing, direction .. " tracked facing")
    assert(world.pose.facing == expectedFacing, direction .. " physical facing")
    assert(startPose.facing == 2, direction .. " must not mutate input pose")
end

checkTurn("left", false, 2, "TURN_FAILED")
checkTurn("right", false, 2, "TURN_FAILED")
checkTurn("left", true, 1, "POSE_TURNED")
checkTurn("right", true, 3, "POSE_TURNED")

-- Crossing north exercises the negative left-turn intermediate explicitly.
for facing = 0, 3 do
    local pose = assert(Pose.new(0, 0, 0, facing))
    local expectedLeft = (facing + 3) % 4
    local expectedRight = (facing + 1) % 4
    local left, leftResult = Pose.afterTurn(pose, "left", true)
    local right, rightResult = Pose.afterTurn(pose, "right", true)
    assert(leftResult.ok and left.facing == expectedLeft, "left normalization from " .. facing)
    assert(rightResult.ok and right.facing == expectedRight, "right normalization from " .. facing)
end

local north = assert(Pose.new(0, 0, 0, 0))
local west, westResult = Pose.afterTurn(north, "left", true)
assert(westResult.ok and west.facing == 3, "left from north wraps to west")
local returnedNorth, northResult = Pose.afterTurn(west, "right", true)
assert(northResult.ok and returnedNorth.facing == 0, "right from west wraps to north")
print("navigation pose turn checks passed")
