-- Fixed V1 surface entry: four level moves from base to the stairs mouth,
-- with an exact movement-only reverse over the known-clear route.
local Contracts = require("src.core.contracts")
local Pose = require("src.navigation.pose")
local Result = require("src.safety.result")

local SurfaceEntry = { LENGTH = 4 }

local function copyPose(pose)
    return { x = pose.x, y = pose.y, z = pose.z, facing = pose.facing }
end

local function samePose(left, right)
    return Contracts.isPose(left) and Contracts.isPose(right)
        and left.x == right.x
        and left.y == right.y
        and left.z == right.z
        and left.facing == right.facing
end

local function expectedAfter(pose, movement, count)
    local expected = copyPose(pose)
    for _ = 1, count do
        expected = assert(Pose.afterMove(expected, movement, true))
    end
    return expected
end

local function withCompleted(outcome, completed)
    local reported = {}
    for key, value in pairs(outcome) do reported[key] = value end
    reported.completed = completed
    return reported
end

local function runMoves(startPose, movement, move)
    local current = copyPose(startPose)
    for completed = 0, SurfaceEntry.LENGTH - 1 do
        local expected = assert(Pose.afterMove(current, movement, true))
        local updated, outcome = move(movement)
        if not Contracts.isResult(outcome) then
            return current, Result.new(false, "INVALID_NAVIGATION_OUTCOME",
                "Checked surface-entry movement returned no structured outcome.", {
                    completed = completed,
                })
        end
        if outcome.ok ~= true then
            if Contracts.isPose(updated) and not samePose(updated, current) then
                return current, Result.new(false, "POSITION_ERROR",
                    "Failed surface-entry movement changed the reported pose.", {
                        completed = completed,
                    })
            end
            return current, withCompleted(outcome, completed)
        end
        if not samePose(updated, expected) then
            if Contracts.isPose(updated) then current = copyPose(updated) end
            return current, Result.new(false, "POSITION_ERROR",
                "Surface-entry movement returned an unexpected pose.", {
                    completed = completed + 1,
                })
        end
        current = copyPose(updated)
    end
    return current, nil
end

function SurfaceEntry.mouthPose(origin)
    if not Contracts.isPose(origin) then return nil end
    return expectedAfter(origin, "forward", SurfaceEntry.LENGTH)
end

function SurfaceEntry.enter(options)
    if type(options) ~= "table" or not Contracts.isPose(options.pose)
        or type(options.move) ~= "function" then
        return type(options) == "table" and options.pose or nil,
            Result.new(false, "INVALID_SURFACE_ENTRY_OPTIONS")
    end

    local startPose = copyPose(options.pose)
    local current, failure = runMoves(startPose, "forward", options.move)
    if failure then return current, failure end

    local expected = SurfaceEntry.mouthPose(startPose)
    if not samePose(current, expected) then
        return current, Result.new(false, "POSITION_ERROR",
            "Surface entry did not reach the stairs mouth.")
    end
    return current, Result.new(true, "SURFACE_ENTRY_COMPLETE", nil, {
        completed = SurfaceEntry.LENGTH,
    })
end

function SurfaceEntry.returnToOrigin(options)
    if type(options) ~= "table" or not Contracts.isPose(options.pose)
        or not Contracts.isPose(options.origin) or type(options.move) ~= "function" then
        return type(options) == "table" and options.pose or nil,
            Result.new(false, "INVALID_SURFACE_ENTRY_OPTIONS")
    end

    local origin = copyPose(options.origin)
    local expectedMouth = SurfaceEntry.mouthPose(origin)
    if not samePose(options.pose, expectedMouth) then
        return copyPose(options.pose), Result.new(false, "POSITION_ERROR",
            "Surface-entry return must start at the recorded stairs mouth.")
    end

    local current, failure = runMoves(options.pose, "back", options.move)
    if failure then return current, failure end
    if not samePose(current, origin) then
        return current, Result.new(false, "POSITION_ERROR",
            "Surface-entry reverse did not restore the origin pose.")
    end
    return current, Result.new(true, "SURFACE_ORIGIN_RESTORED", nil, {
        completed = SurfaceEntry.LENGTH,
    })
end

return SurfaceEntry
