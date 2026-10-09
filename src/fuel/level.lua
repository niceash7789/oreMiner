-- Formatting and accounting for CC:Tweaked's numeric or "unlimited" fuel level.
local FuelLevel = {}

function FuelLevel.isUnlimited(level)
    return level == "unlimited"
end

function FuelLevel.format(level)
    if FuelLevel.isUnlimited(level) then return "unlimited" end
    if type(level) == "number" then return tostring(level) end
    return "unavailable"
end

function FuelLevel.consumed(before, after)
    if type(before) ~= "number" or type(after) ~= "number" then return 0 end
    return math.max(0, before - after)
end

return FuelLevel
