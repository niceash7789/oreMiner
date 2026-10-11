local Lighting = require("src.lighting.right_wall")
local Pose = require("src.navigation.pose")
local Result = require("src.safety.result")

local expected = {
    { x = 3, y = -3, z = 4, facing = 1 },
    { x = 2, y = -3, z = 5, facing = 2 },
    { x = 1, y = -3, z = 4, facing = 3 },
    { x = 2, y = -3, z = 3, facing = 0 },
}
for outbound = 0, 3 do
    local side = assert(Lighting.rightSide({ x = 2, y = -3, z = 4, facing = (outbound + 2) % 4 }, outbound))
    assert(side.x == expected[outbound + 1].x and side.y == expected[outbound + 1].y
        and side.z == expected[outbound + 1].z and side.facing == expected[outbound + 1].facing,
        "route right-side geometry must be independent of current turtle facing")
end
local invalidFrame, invalidCode = Lighting.rightSide({ x = 0, y = 0, z = 0 }, 4)
assert(invalidFrame == nil and invalidCode == "LIGHTING_INVALID_FRAME")

local function run(startFacing, outboundFacing)
    local pose = { x = 2, y = -3, z = 4, facing = startFacing }
    local current = { x = pose.x, y = pose.y, z = pose.z, facing = pose.facing }
    local worldFacing = startFacing
    local placedFacing
    local turns = 0
    local result = Lighting.placeRight({
        pose = pose,
        outboundFacing = outboundFacing,
        turn = function(direction)
            local updated, outcome = Pose.afterTurn(current, direction, true)
            current = updated
            worldFacing = updated.facing
            turns = turns + 1
            return updated, outcome
        end,
        dig = function() return Result.new(true, "CLEARED") end,
        place = function()
            placedFacing = worldFacing
            return Result.new(true, "PLACED")
        end,
    })
    assert(result.ok and result.code == "TORCH_PLACED")
    assert(placedFacing == (outboundFacing + 1) % 4,
        "torch must face the route-defined outbound right wall")
    assert(worldFacing == startFacing and turns <= 4,
        "helper must restore facing using checked turns")
end

local shaftDigCalls, shaftPlaceCalls = 0, 0
local shaftPose = { x = 3, y = -8, z = -13, facing = 1 }
local shaftResult = Lighting.placeRight({
    pose = shaftPose, outboundFacing = 0, alreadyClear = true,
    turn = function(direction)
        local updated, outcome = Pose.afterTurn(shaftPose, direction, true)
        shaftPose = updated
        return updated, outcome
    end,
    dig = function() shaftDigCalls = shaftDigCalls + 1; return Result.new(true, "DUG") end,
    place = function() shaftPlaceCalls = shaftPlaceCalls + 1; return Result.new(true, "PLACED") end,
    poseNow = function() return shaftPose end,
})
assert(shaftResult.ok and shaftDigCalls == 0 and shaftPlaceCalls == 1,
    "main and branch shaft torches must place in the cleared passage without digging a side niche")
assert(shaftPose.x == 3 and shaftPose.y == -8 and shaftPose.z == -13 and shaftPose.facing == 1,
    "shaft torch placement must leave the turtle at the exact mining pose")

for outbound = 0, 3 do
    for start = 0, 3 do run(start, outbound) end
end

local calls = 0
local failed = Lighting.placeRight({
    pose = { x = 0, y = 0, z = 0, facing = 0 }, outboundFacing = 0,
    turn = function(direction)
        calls = calls + 1
        return Pose.afterTurn({ x = 0, y = 0, z = 0, facing = calls == 1 and 0 or 1 }, direction, false)
    end,
    dig = function() error("must not dig after failed turn") end,
    place = function() error("must not place after failed turn") end,
})
assert(not failed.ok and calls == 1, "failed checked turn must stop before world interaction")

local digCalls = 0
local current = { x = 0, y = 0, z = 0, facing = 0 }
local digFailure = Lighting.placeRight({
    pose = { x = 0, y = 0, z = 0, facing = 0 }, outboundFacing = 0,
    turn = function(direction)
        local updated = Pose.afterTurn(current, direction, true)
        current = updated
        return updated, Result.new(true, "TURNED")
    end,
    dig = function() digCalls = digCalls + 1; return Result.new(false, "DIG_BLOCKED") end,
    place = function() error("must not place after failed dig") end,
})
assert(not digFailure.ok and digFailure.code == "DIG_BLOCKED" and digCalls == 1,
    "failed niche clear must restore facing and avoid placement")

local clearDigCalls, clearPlaceCalls = 0, 0
local clearPose = { x = 4, y = -4, z = -8, facing = 0 }
local alreadyClear = Lighting.placeRight({
    pose = clearPose, outboundFacing = 0,
    turn = function(direction)
        local updated, outcome = Pose.afterTurn(clearPose, direction, true)
        clearPose = updated
        return updated, outcome
    end,
    alreadyClear = true,
    dig = function() clearDigCalls = clearDigCalls + 1; return Result.new(true, "DUG") end,
    place = function() clearPlaceCalls = clearPlaceCalls + 1; return Result.new(true, "PLACED") end,
    poseNow = function() return clearPose end,
})
assert(alreadyClear.ok and clearDigCalls == 0 and clearPlaceCalls == 1,
    "an already-cleared passage placement must place once without invoking any dig callback")
assert(clearPose.x == 4 and clearPose.y == -4 and clearPose.z == -8 and clearPose.facing == 0,
    "an already-cleared passage placement must restore its exact pose and facing")

local driftingPose = { x = 0, y = 0, z = 0, facing = 0 }
local poseMismatch = Lighting.placeRight({
    pose = { x = 0, y = 0, z = 0, facing = 0 }, outboundFacing = 0,
    turn = function(direction)
        local updated = Pose.afterTurn({ x = 0, y = 0, z = 0, facing = driftingPose.facing }, direction, true)
        driftingPose.facing = updated.facing
        return updated, Result.new(true, "TURNED")
    end,
    dig = function() driftingPose.x = 1; return Result.new(true, "CLEARED") end,
    place = function() return Result.new(true, "PLACED") end,
    poseNow = function() return driftingPose end,
})
assert(not poseMismatch.ok and poseMismatch.code == "LIGHTING_POSE_MISMATCH",
    "helper must reject coordinate drift even when facing is restored")

print("right-wall lighting checks passed")
