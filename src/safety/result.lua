local Result = {}

function Result.new(ok, code, message, fields)
    local outcome = {
        ok = ok == true,
        code = code,
        message = message,
    }
    if type(fields) == "table" then
        for key, value in pairs(fields) do outcome[key] = value end
    end
    return outcome
end

function Result.isSuccess(outcome)
    return type(outcome) == "table" and outcome.ok == true
end

return Result
