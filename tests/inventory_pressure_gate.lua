local Gate = require("src.inventory.pressure_gate")
local Pressure = require("src.inventory.pressure")
local defaults = require("src.config.defaults")

-- Exercise the configured threshold at the real pre-dig boundary. The service
-- callback models the completed checkpointed unload before work is admitted.
local slotCounts = {}
local turtleApi = { getItemCount = function(slot) return slotCounts[slot] or 0 end }
for slot = 1, 13 do slotCounts[slot] = 1 end
local physicalDigCalls = 0
local preDigServices = 0
local function tunnelDig()
    physicalDigCalls = physicalDigCalls + 1
    return true
end

local thresholdAllowed = Gate.beforeDig(function()
    return Pressure.reached(turtleApi, defaults.inventory.returnThreshold)
end, function()
    preDigServices = preDigServices + 1
    return true, "SERVICE_COMPLETE"
end)
if thresholdAllowed then tunnelDig() end
assert(thresholdAllowed == true and physicalDigCalls == 1 and preDigServices == 0,
    "13 occupied slots should allow tunnel dig without a service trip")

slotCounts[14] = 1
thresholdAllowed = Gate.beforeDig(function()
    return Pressure.reached(turtleApi, defaults.inventory.returnThreshold)
end, function()
    preDigServices = preDigServices + 1
    -- A completed unload leaves pressure below threshold.
    slotCounts[14] = nil
    return true, "SERVICE_COMPLETE"
end)
if thresholdAllowed then tunnelDig() end
assert(thresholdAllowed == true and physicalDigCalls == 2 and preDigServices == 1,
    "14 occupied slots must complete service before the tunnel dig")

slotCounts[14] = 1
thresholdAllowed = Gate.beforeDig(function()
    return Pressure.reached(turtleApi, defaults.inventory.returnThreshold)
end, function()
    preDigServices = preDigServices + 1
    return false, "NO_OUTPUT_CHEST"
end)
if thresholdAllowed then tunnelDig() end
assert(thresholdAllowed == false and physicalDigCalls == 2
    and preDigServices == 2,
    "failed threshold service must prevent the physical tunnel dig")

local digs = 0
local services = 0
local allowed, code = Gate.beforeDig(function() return false end, function()
    services = services + 1
    return true
end)
if allowed then digs = digs + 1 end
assert(allowed and code == "PRESSURE_CLEAR" and services == 0 and digs == 1,
    "clear inventory pressure should admit digging without a service trip")

allowed, code = Gate.beforeDig(function() return true end, function()
    services = services + 1
    return true, "SERVICE_COMPLETE"
end)
if allowed then digs = digs + 1 end
assert(allowed and code == "SERVICE_COMPLETE" and services == 1 and digs == 2,
    "14-slot pressure should finish service before allowing the seed dig")

allowed, code = Gate.beforeDig(function() return true end, function()
    services = services + 1
    return false, "NO_OUTPUT_CHEST"
end)
if allowed then digs = digs + 1 end
assert(not allowed and code == "NO_OUTPUT_CHEST" and services == 2 and digs == 2,
    "failed service must prevent the dig and preserve its specific error")

local servicesBeforeProbeFailure = services
allowed, code = Gate.beforeDig(function()
    error("pressure probe failure")
end, function()
    services = services + 1
    return true
end)
assert(not allowed and code == "INVENTORY_PRESSURE_CHECK_FAILED"
    and services == servicesBeforeProbeFailure,
    "a failed pressure probe must deny admission without starting service")

allowed, code = Gate.beforeDig(function() return nil end, function()
    services = services + 1
    return true
end)
assert(not allowed and code == "INVENTORY_PRESSURE_CHECK_FAILED"
    and services == servicesBeforeProbeFailure,
    "an unverifiable pressure probe must deny admission")

allowed, code = Gate.beforeDig(function() return true end, function()
    error("service failure")
end)
assert(not allowed and code == "INVENTORY_SERVICE_FAILED",
    "a service exception must deny admission")

print("inventory pressure gate checks passed")
