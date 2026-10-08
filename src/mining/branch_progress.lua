-- Runs the configured outbound branch steps without treating a partial route as complete.
local BranchProgress = {}

local function failure(code, message, completed, requested)
    return {
        ok = false,
        code = code,
        message = message,
        completed = completed,
        requested = requested,
    }
end

function BranchProgress.run(length, step)
    if type(length) ~= "number" or length < 1 or length ~= math.floor(length)
        or type(step) ~= "function" then
        return failure("INVALID_BRANCH_PROGRESS", "A positive branch length and step function are required", 0, length)
    end

    for index = 1, length do
        local outcome = step(index)
        if outcome ~= true then
            if type(outcome) == "table" and outcome.ok == true then
                -- Typed success is valid, but preserve the legacy boolean
                -- contract for step coordinators that only inspect true.
            elseif type(outcome) == "table" and outcome.ok == false then
                outcome.completed = index - 1
                outcome.requested = length
                return outcome
            elseif outcome == false then
                return failure("BRANCH_SHORTENED", "Branch stopped before its configured length", index - 1, length)
            else
                return failure("INVALID_STEP_OUTCOME", "Branch step returned no typed outcome", index - 1, length)
            end
        end
    end

    return { ok = true, code = "BRANCH_LENGTH_REACHED", completed = length, requested = length }
end

return BranchProgress
