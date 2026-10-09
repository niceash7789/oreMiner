-- Clear a flat, three-wide by three-long landing with three blocks of
-- headroom. Caller starts at rear-centre/bottom and the operation ends at
-- centre-centre/bottom, one block forward.
local Contracts = require("src.core.contracts")
local Pose = require("src.navigation.pose")
local Result = require("src.safety.result")

local Landing = {}

local function samePose(left, right)
    return Contracts.isPose(left) and Contracts.isPose(right)
        and left.x == right.x and left.y == right.y
        and left.z == right.z and left.facing == right.facing
end

function Landing.prepare(options)
    if type(options) ~= "table" or not Contracts.isPose(options.pose)
        or type(options.move) ~= "function" or type(options.turn) ~= "function"
        or type(options.clear) ~= "function" then
        return type(options) == "table" and options.pose or nil,
            Result.new(false, "INVALID_LANDING_OPTIONS")
    end

    local current = {
        x = options.pose.x, y = options.pose.y,
        z = options.pose.z, facing = options.pose.facing,
    }

    local function applyMove(direction)
        local expected, poseOutcome = Pose.afterMove(current, direction, true)
        if not poseOutcome.ok then return poseOutcome end
        local updated, outcome = options.move(direction)
        if not Contracts.isResult(outcome) then
            return Result.new(false, "INVALID_NAVIGATION_OUTCOME")
        end
        if outcome.ok ~= true then
            if Contracts.isPose(updated) and not samePose(updated, current) then
                return Result.new(false, "POSITION_ERROR", "Failed move changed the landing pose.")
            end
            return outcome
        end
        if not samePose(updated, expected) then
            return Result.new(false, "POSITION_ERROR", "Landing move returned an unexpected pose.")
        end
        current = { x = updated.x, y = updated.y, z = updated.z, facing = updated.facing }
        return outcome
    end

    local function applyTurn(direction)
        local expected, poseOutcome = Pose.afterTurn(current, direction, true)
        if not poseOutcome.ok then return poseOutcome end
        local updated, outcome = options.turn(direction)
        if not Contracts.isResult(outcome) then
            return Result.new(false, "INVALID_NAVIGATION_OUTCOME")
        end
        if outcome.ok ~= true then
            if Contracts.isPose(updated) and not samePose(updated, current) then
                return Result.new(false, "POSITION_ERROR", "Failed turn changed the landing pose.")
            end
            return outcome
        end
        if not samePose(updated, expected) then
            return Result.new(false, "POSITION_ERROR", "Landing turn returned an unexpected pose.")
        end
        current = { x = updated.x, y = updated.y, z = updated.z, facing = updated.facing }
        return outcome
    end

    local function clear(direction)
        local outcome = options.clear(direction)
        if not Contracts.isResult(outcome) then
            return Result.new(false, "INVALID_DIG_CLEAR_OUTCOME")
        end
        return outcome
    end

    local function clearThreeHigh()
        local cleared = clear("up")
        if cleared.ok ~= true then return cleared end
        local moved = applyMove("up")
        if moved.ok ~= true then return moved end
        cleared = clear("up")
        if cleared.ok ~= true then
            local restored = applyMove("down")
            return restored.ok == true and cleared or restored
        end
        return applyMove("down")
    end

    local function clearSide(direction)
        local turned = applyTurn(direction)
        if turned.ok ~= true then return turned end
        local cleared = clear("forward")
        if cleared.ok ~= true then
            local restored = applyTurn(direction == "left" and "right" or "left")
            return restored.ok == true and cleared or restored
        end
        local moved = applyMove("forward")
        if moved.ok ~= true then
            local restored = applyTurn(direction == "left" and "right" or "left")
            return restored.ok == true and moved or restored
        end
        local highClear = clearThreeHigh()
        if highClear.ok ~= true then return highClear end
        local returned = applyMove("back")
        if returned.ok ~= true then return returned end
        return applyTurn(direction == "left" and "right" or "left")
    end

    local function clearRow()
        local outcome = clearThreeHigh()
        if outcome.ok ~= true then return outcome end
        outcome = clearSide("left")
        if outcome.ok ~= true then return outcome end
        return clearSide("right")
    end

    local start = { x = current.x, y = current.y, z = current.z, facing = current.facing }
    local outcome = clearRow()
    if outcome.ok ~= true then return current, outcome end

    for row = 1, 2 do
        outcome = clear("forward")
        if outcome.ok then outcome = applyMove("forward") end
        if outcome.ok then outcome = clearRow() end
        if outcome.ok ~= true then
            return current, Result.new(false, outcome.code or "LANDING_CLEAR_FAILED",
                outcome.message, { row = row })
        end
    end

    outcome = applyMove("back")
    if outcome.ok ~= true then return current, outcome end
    local expected = assert(Pose.afterMove(start, "forward", true))
    if not samePose(current, expected) then
        return current, Result.new(false, "POSITION_ERROR", "Landing carve did not finish at its canonical centre.")
    end
    return current, Result.new(true, "LANDING_CARVED")
end

return Landing
