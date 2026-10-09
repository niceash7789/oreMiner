local Result = {}

function Result.new(ok, code, message, fields)
    if type(code) ~= "string" or #code == 0 then
        error("result code must be a non-empty string")
    end
    local outcome = {
        ok = ok == true,
        code = code,
        message = message,
        retryable = false,
    }
    if type(fields) == "table" then
        for key, value in pairs(fields) do outcome[key] = value end
    end
    outcome.retryable = outcome.retryable == true
    return outcome
end

function Result.isSuccess(outcome)
    return type(outcome) == "table" and outcome.ok == true
end

function Result.isResult(outcome)
    return type(outcome) == "table" and type(outcome.ok) == "boolean"
        and type(outcome.code) == "string" and #outcome.code > 0
        and (outcome.message == nil or type(outcome.message) == "string")
        and type(outcome.retryable) == "boolean"
end

return Result
