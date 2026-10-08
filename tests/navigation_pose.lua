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

-- Successful API movement advances both the simulated turtle and tracked pose.
local world = FakeTurtle.new(start)
local apiResult = world:move("forward", true)
local tracked, result = Pose.afterMove(start, "forward", apiResult)
assert(result.ok == true, "successful movement should succeed")
assertPose(world.pose, { x = 0, y = 0, z = -1, facing = 0 }, "simulated turtle success")
assertPose(tracked, world.pose, "tracked pose after success")
assertPose(start, expectedStart, "original input after success")

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
print("navigation pose turn checks passed")
