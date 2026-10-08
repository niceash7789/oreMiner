-- Run an inventory helper without leaving the turtle on a different slot.
local SlotGuard = {}

local function failure(code, message)
    return { ok = false, code = code, message = message, retryable = false }
end

function SlotGuard.run(turtleApi, operation)
    if type(turtleApi) ~= "table"
        or type(turtleApi.getSelectedSlot) ~= "function"
        or type(turtleApi.select) ~= "function"
        or type(operation) ~= "function" then
        return failure("INVALID_ARGUMENT", "turtle API and operation are required")
    end

    local gotSlot, originalSlot = pcall(turtleApi.getSelectedSlot)
    if not gotSlot or type(originalSlot) ~= "number" then
        return failure("SLOT_READ_FAILED", "could not read the selected slot")
    end

    local operationOk, value = pcall(operation)
    local restoredCall, restored = pcall(turtleApi.select, originalSlot)
    if not restoredCall or restored ~= true then
        return failure("SLOT_RESTORE_FAILED", "could not restore the selected slot")
    end

    if not operationOk then
        return failure("OPERATION_FAILED", tostring(value))
    end

    return { ok = true, value = value }
end

return SlotGuard
