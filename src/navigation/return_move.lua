-- Checked movement along an edge already recorded as traversed.
local ReturnMove = {}

local function failure(code, message, attempts)
    return { ok = false, code = code, message = message, retryable = false, attempts = attempts }
end

function ReturnMove.run(options)
    if type(options) ~= "table" or type(options.hasEdge) ~= "function"
        or type(options.move) ~= "function" or type(options.maxAttempts) ~= "number"
        or options.maxAttempts < 1 or options.maxAttempts % 1 ~= 0 then
        return failure("INVALID_RETURN_MOVE", "Invalid return movement policy", 0)
    end
    if options.hasEdge() ~= true then
        return failure("RETURN_ROUTE_UNKNOWN", "Return step is not a previously cleared route edge", 0)
    end
    for attempt = 1, options.maxAttempts do
        if options.move() == true then
            return { ok = true, code = "RETURN_MOVE_COMPLETE", attempts = attempt }
        end
        if options.recover then options.recover(attempt) end
    end
    return failure("RETURN_BLOCKED", "Recorded return route remains blocked after bounded recovery", options.maxAttempts)
end

return ReturnMove
