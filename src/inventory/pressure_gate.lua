-- Admission helper for world-changing work that must not begin under pressure.
local PressureGate = {}

function PressureGate.beforeDig(pressureReached, serviceIfNeeded)
    if type(pressureReached) ~= "function" or type(serviceIfNeeded) ~= "function" then
        return false, "INVALID_ARGUMENT"
    end
    local probeOk, pressure = pcall(pressureReached)
    if not probeOk then return false, "INVENTORY_PRESSURE_CHECK_FAILED" end
    if pressure == false then return true, "PRESSURE_CLEAR" end
    if pressure ~= true then return false, "INVENTORY_PRESSURE_CHECK_FAILED" end
    local serviceOk, serviced, code = pcall(serviceIfNeeded)
    if not serviceOk then return false, "INVENTORY_SERVICE_FAILED" end
    if serviced ~= true then return false, code or "INVENTORY_SERVICE_FAILED" end
    return true, "SERVICE_COMPLETE"
end

return PressureGate
