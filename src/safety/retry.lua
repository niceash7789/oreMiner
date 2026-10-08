local Retry = {}

local MAX_ATTEMPTS = 64

function Retry.result(ok, code, message, retryable, attempts)
    return {
        ok = ok == true,
        code = code,
        message = message,
        retryable = retryable == true,
        attempts = attempts or 0,
    }
end

local function validLimit(limit)
    return type(limit) == "number"
        and limit == math.floor(limit)
        and limit >= 1
        and limit <= MAX_ATTEMPTS
end

-- Runs a typed operation no more than limit times. The operation decides
-- whether an outcome is safe to retry; exhausting the budget is explicit.
function Retry.run(limit, exhaustedCode, operation)
    if not validLimit(limit) or type(exhaustedCode) ~= "string"
        or exhaustedCode == "" or type(operation) ~= "function" then
        return Retry.result(false, "INVALID_RETRY_POLICY", "Invalid retry policy", false, 0)
    end

    for attempt = 1, limit do
        local outcome = operation(attempt)
        if type(outcome) ~= "table" or type(outcome.ok) ~= "boolean"
            or type(outcome.retryable) ~= "boolean" then
            return Retry.result(false, "INVALID_OUTCOME", "Operation returned an invalid outcome", false, attempt)
        end

        if outcome.ok or not outcome.retryable then
            outcome.attempts = attempt
            return outcome
        end
    end

    return Retry.result(false, exhaustedCode, "Retry limit reached", false, limit)
end

return Retry
