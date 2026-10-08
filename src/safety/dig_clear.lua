local DigClear = {}
local Result = require("src.safety.result")

local function result(ok, code, message, attempts, dug)
    return Result.new(ok, code, message, {
        attempts = attempts,
        dug = dug,
    })
end

function DigClear.run(options)
    if type(options) ~= "table"
        or type(options.detect) ~= "function"
        or type(options.dig) ~= "function"
        or type(options.now) ~= "function"
        or type(options.maxAttempts) ~= "number"
        or options.maxAttempts < 1
        or options.maxAttempts % 1 ~= 0
        or type(options.maxElapsed) ~= "number"
        or options.maxElapsed <= 0 then
        return result(false, "INVALID_DIG_CLEAR_POLICY", "Invalid bounded dig policy", 0, 0)
    end

    local started = options.now()
    local attempts = 0
    local dug = 0

    while true do
        if options.now() - started >= options.maxElapsed then
            return result(false, "DIG_TIME_EXHAUSTED", "Dig-clear time limit reached", attempts, dug)
        end

        local detected = options.detect()
        if options.now() - started >= options.maxElapsed then
            return result(false, "DIG_TIME_EXHAUSTED", "Dig-clear time limit reached", attempts, dug)
        end
        if not detected then
            return result(true, "NO_BLOCK", nil, attempts, dug)
        end

        if attempts >= options.maxAttempts then
            return result(false, "DIG_ATTEMPTS_EXHAUSTED", "Dig-clear attempt limit reached", attempts, dug)
        end

        attempts = attempts + 1
        if options.dig() then
            dug = dug + 1
            if options.wait then options.wait() end
        else
            return result(false, "UNBREAKABLE_BLOCK", "Turtle could not dig the detected block", attempts, dug)
        end
    end
end

return DigClear
