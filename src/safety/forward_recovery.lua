-- Bounded recovery for an unexpected failed forward move.
local Result = require("src.safety.result")

local ForwardRecovery = {}

local function validLimit(value)
    return type(value) == "number" and value >= 1
        and value == math.floor(value) and value <= 64
end

function ForwardRecovery.run(options)
    if type(options) ~= "table" or type(options.move) ~= "function"
        or type(options.detect) ~= "function" or type(options.digClear) ~= "function"
        or type(options.attack) ~= "function" or type(options.wait) ~= "function"
        or not validLimit(options.maxMoveRetries)
        or not validLimit(options.maxEntityRetries) then
        return Result.new(false, "INVALID_FORWARD_RECOVERY_POLICY")
    end

    local moveRetries = 0
    local entityRetries = 0
    while true do
        local moved, moveOutcome = options.move()
        if type(moved) ~= "boolean" then
            return Result.new(false, "INVALID_MOVE_OUTCOME", "Movement callback must return a boolean")
        end
        if moved == true then
            return Result.new(true, "FORWARD_MOVE_COMPLETE", nil, {
                moveRetries = moveRetries,
                entityRetries = entityRetries,
            })
        end
        if type(moveOutcome) == "table" and moveOutcome.code ~= "MOVE_FAILED" then
            return moveOutcome
        end

        local detected = options.detect()
        if type(detected) ~= "boolean" then
            return Result.new(false, "INVALID_DETECTION_OUTCOME", "Detection callback must return a boolean", {
                moveRetries = moveRetries,
                entityRetries = entityRetries,
            })
        end
        if detected then
            if moveRetries >= options.maxMoveRetries then
                return Result.new(false, "BLOCKED", "Forward obstruction recovery limit reached", {
                    moveRetries = moveRetries,
                    entityRetries = entityRetries,
                })
            end
            local cleared = options.digClear()
            if type(cleared) ~= "table" or cleared.ok ~= true then
                return type(cleared) == "table" and cleared
                    or Result.new(false, "INVALID_DIG_CLEAR_OUTCOME")
            end
            moveRetries = moveRetries + 1
        else
            if entityRetries >= options.maxEntityRetries then
                return Result.new(false, "ENTITY_BLOCKED", "Entity still blocks forward movement", {
                    moveRetries = moveRetries,
                    entityRetries = entityRetries,
                })
            end
            if entityRetries + 1 == options.maxEntityRetries and options.warn then
                options.warn()
            end
            entityRetries = entityRetries + 1
            options.attack()
            options.wait()
        end
    end
end

return ForwardRecovery
