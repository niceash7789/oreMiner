-- One deterministic 3-wide by 3-tall descending stairs slice.
-- Callers provide bounded clear operations and checked, persisted navigation
-- callbacks. This module owns only the slice geometry and local unwind.
local ActionStack = require("src.navigation.action_stack")
local Contracts = require("src.core.contracts")
local Pose = require("src.navigation.pose")
local Result = require("src.safety.result")

local StairSlice = {}

local function samePose(left, right)
    return Contracts.isPose(left) and Contracts.isPose(right)
        and left.x == right.x
        and left.y == right.y
        and left.z == right.z
        and left.facing == right.facing
end

local function invalidOptions()
    return Result.new(false, "INVALID_STAIR_SLICE_OPTIONS",
        "A valid pose and checked clear, move, and turn callbacks are required.")
end

local function validateOptions(options, needsClear)
    return type(options) == "table"
        and Contracts.isPose(options.pose)
        and type(options.move) == "function"
        and type(options.turn) == "function"
        and (not needsClear or type(options.clear) == "function")
end

local function copyPose(pose)
    return { x = pose.x, y = pose.y, z = pose.z, facing = pose.facing }
end

local function runner(options)
    local current = copyPose(options.pose)

    local function apply(action)
        local expected, expectedResult
        local updated, outcome
        if action == "forward" or action == "back"
            or action == "up" or action == "down" then
            expected, expectedResult = Pose.afterMove(current, action, true)
            updated, outcome = options.move(action)
        elseif action == "turnLeft" or action == "turnRight" then
            local direction = action == "turnLeft" and "left" or "right"
            expected, expectedResult = Pose.afterTurn(current, direction, true)
            updated, outcome = options.turn(direction)
        else
            return Result.new(false, "INVALID_ROUTE_ACTION", "Unsupported stairs action.")
        end

        if not expectedResult.ok then return expectedResult end
        if not Contracts.isResult(outcome) then
            return Result.new(false, "INVALID_NAVIGATION_OUTCOME",
                "Checked navigation callback returned no structured outcome.")
        end
        if outcome.ok ~= true then
            if Contracts.isPose(updated) and not samePose(updated, current) then
                return Result.new(false, "POSITION_ERROR",
                    "Failed navigation action changed the reported pose.")
            end
            return outcome
        end
        if not samePose(updated, expected) then
            if Contracts.isPose(updated) then current = copyPose(updated) end
            return Result.new(false, "POSITION_ERROR",
                "Checked navigation action returned an unexpected pose.")
        end

        current = copyPose(updated)
        return outcome
    end

    local function clear(direction)
        local outcome = options.clear(direction)
        if not Contracts.isResult(outcome) then
            return Result.new(false, "INVALID_DIG_CLEAR_OUTCOME",
                "Clear callback returned no structured outcome.")
        end
        return outcome
    end

    return {
        apply = apply,
        clear = clear,
        pose = function() return copyPose(current) end,
    }
end

local function unwind(excursion, navigation)
    local inverseFailure
    local outcome = ActionStack.unwind(excursion, function(action)
        local applied = navigation.apply(action)
        if applied.ok ~= true then
            inverseFailure = applied
            return false
        end
        return true
    end)
    if not outcome.ok then
        return inverseFailure or outcome
    end
    return outcome
end

local function enter(excursion, navigation, action)
    local outcome = navigation.apply(action)
    if not outcome.ok then return outcome end
    return ActionStack.record(excursion, action)
end

local function sweepColumn(navigation, turnAction)
    local excursion = ActionStack.new()
    local outcome = enter(excursion, navigation, turnAction)
    if not outcome.ok then return outcome end

    outcome = navigation.clear("forward")
    if outcome.ok then outcome = enter(excursion, navigation, "forward") end
    if outcome.ok then outcome = navigation.clear("up") end
    if outcome.ok then outcome = navigation.clear("down") end

    local restored = unwind(excursion, navigation)
    if not restored.ok then return restored end
    return outcome
end

function StairSlice.descend(options)
    if not validateOptions(options, true) then
        return type(options) == "table" and options.pose or nil, invalidOptions()
    end

    local navigation = runner(options)
    local startPose = copyPose(options.pose)
    local middlePose = assert(Pose.afterMove(startPose, "forward", true))
    local approach = ActionStack.new()

    local outcome = navigation.clear("forward")
    if outcome.ok then outcome = enter(approach, navigation, "forward") end
    if outcome.ok then outcome = navigation.clear("up") end
    if outcome.ok then outcome = navigation.clear("down") end
    if outcome.ok then outcome = sweepColumn(navigation, "turnLeft") end
    if outcome.ok then outcome = sweepColumn(navigation, "turnRight") end
    if not outcome.ok then
        if samePose(navigation.pose(), middlePose) then
            local restored = unwind(approach, navigation)
            if not restored.ok then return navigation.pose(), restored end
        end
        return navigation.pose(), outcome
    end

    if not samePose(navigation.pose(), middlePose) then
        return navigation.pose(), Result.new(false, "POSITION_ERROR",
            "Stairs sweep did not restore the centreline pose and facing.")
    end

    outcome = navigation.apply("down")
    if not outcome.ok then
        local restored = unwind(approach, navigation)
        if not restored.ok then return navigation.pose(), restored end
        return navigation.pose(), outcome
    end

    local expected = assert(Pose.afterMove(middlePose, "down", true))
    if not samePose(navigation.pose(), expected) then
        return navigation.pose(), Result.new(false, "POSITION_ERROR",
            "Stairs slice did not finish at its centre-bottom checkpoint.")
    end

    return navigation.pose(), Result.new(true, "STAIR_SLICE_COMPLETE",
        "Stairs slice cleared and centre-bottom checkpoint reached.")
end

function StairSlice.climb(options)
    if not validateOptions(options, false) then
        return type(options) == "table" and options.pose or nil, invalidOptions()
    end

    local navigation = runner(options)
    local startPose = copyPose(options.pose)
    local outcome = navigation.apply("up")
    if outcome.ok then outcome = navigation.apply("back") end
    if not outcome.ok then return navigation.pose(), outcome end

    local above = assert(Pose.afterMove(startPose, "up", true))
    local expected = assert(Pose.afterMove(above, "back", true))
    if not samePose(navigation.pose(), expected) then
        return navigation.pose(), Result.new(false, "POSITION_ERROR",
            "Inverse stairs climb did not reach the previous checkpoint.")
    end

    return navigation.pose(), Result.new(true, "STAIR_SLICE_CLIMBED",
        "Inverse stairs slice climbed without excavation.")
end

return StairSlice
