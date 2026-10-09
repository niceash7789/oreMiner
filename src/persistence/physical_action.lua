-- Persist intent and commit around one physical turtle action.
local Result = require("src.safety.result")

local PhysicalAction = {}

function PhysicalAction.run(session, kind, direction, pose, route, config, invoke)
    if type(session) ~= "table" or type(session.beginAction) ~= "function"
        or type(session.commitAction) ~= "function" or type(session.cancelAction) ~= "function"
        or (kind ~= "move" and kind ~= "turn" and kind ~= "dig")
        or type(direction) ~= "string" or type(invoke) ~= "function" then
        return Result.new(false, "INVALID_PHYSICAL_ACTION")
    end

    local saved, saveCode = session:beginAction(kind, direction, pose, route, config)
    if saved ~= true then
        return Result.new(false, saveCode or "ACTION_INTENT_FAILED")
    end

    -- An exception after durable intent is indistinguishable from a crash
    -- after the world changed. Leave the intent pending for safe-stop recovery.
    local called, succeeded = pcall(invoke)
    if not called then
        return Result.new(false, "ACTION_RESULT_UNCERTAIN", tostring(succeeded))
    end

    if succeeded == true then
        local committed, commitCode = session:commitAction(pose, route, config)
        if committed ~= true then
            return Result.new(false, commitCode or "ACTION_COMMIT_FAILED")
        end
        return Result.new(true, "ACTION_COMMITTED")
    end

    local cancelled, cancelCode = session:cancelAction(pose, route, config)
    if cancelled ~= true then
        return Result.new(false, cancelCode or "ACTION_CANCEL_FAILED")
    end
    return Result.new(false, kind == "dig" and "DIG_FAILED" or "ACTION_FAILED")
end

return PhysicalAction
