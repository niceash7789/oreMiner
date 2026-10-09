local DigClear = {}
local Result = require("src.safety.result")
local MAX_ATTEMPTS = 64

local function finitePositive(value)
    return type(value) == "number" and value == value
        and value > 0 and value < math.huge
end

local function result(ok, code, message, attempts, dug)
    return Result.new(ok, code, message, {
        attempts = attempts,
        dug = dug,
    })
end

function DigClear.run(options)
    if type(options) ~= "table"
        or type(options.detect) ~= "function"
        or (options.inspect ~= nil and type(options.inspect) ~= "function")
        or (options.onBlock ~= nil and type(options.onBlock) ~= "function")
        or type(options.dig) ~= "function"
        or type(options.now) ~= "function"
        or type(options.maxAttempts) ~= "number"
        or options.maxAttempts < 1
        or options.maxAttempts % 1 ~= 0
        or options.maxAttempts > MAX_ATTEMPTS
        or not finitePositive(options.maxElapsed) then
        return result(false, "INVALID_DIG_CLEAR_POLICY", "Invalid bounded dig policy", 0, 0)
    end

    local started = options.now()
    if not finitePositive(started + 1) then
        return result(false, "INVALID_DIG_CLEAR_CLOCK", "Dig-clear clock returned an invalid time", 0, 0)
    end
    local attempts = 0
    local dug = 0
    local lastBlock

    while true do
        if options.now() - started >= options.maxElapsed then
            return result(false, "BLOCKED", "Dig-clear time limit reached", attempts, dug)
        end

        local detected = options.detect()
        if options.now() - started >= options.maxElapsed then
            return result(false, "BLOCKED", "Dig-clear time limit reached", attempts, dug)
        end
        if not detected then
            return result(true, "NO_BLOCK", nil, attempts, dug)
        end

        if options.inspect then
            local block = options.inspect()
            if type(block) ~= "table" or type(block.name) ~= "string" then
                return result(false, "INVALID_BLOCK_INSPECTION",
                    "Dig-clear inspection returned no block identity", attempts, dug)
            end
            lastBlock = block.name
        end

        if attempts >= options.maxAttempts then
            return result(false, "BLOCKED", "Dig-clear attempt limit reached", attempts, dug)
        end

        attempts = attempts + 1
        if options.dig() then
            dug = dug + 1
            if options.onBlock then options.onBlock(lastBlock, attempts) end
            if options.wait then options.wait() end
        else
            return result(false, "UNBREAKABLE_BLOCK", "Turtle could not dig the detected block", attempts, dug)
        end
    end
end

return DigClear
