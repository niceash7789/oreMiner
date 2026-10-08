-- Fuel gate for a single proposed move, using the caller's current route estimate.
local FuelPolicy = {}

function FuelPolicy.canMove(level, requiredFuel, refuel, readFuel)
    if level == "unlimited" then
        return true, "UNLIMITED_FUEL"
    end

    if type(level) ~= "number" or type(requiredFuel) ~= "number" then
        return false, "INVALID_FUEL_LEVEL"
    end

    if level < requiredFuel then
        if type(refuel) ~= "function" or not refuel(requiredFuel) then
            return false, "INSUFFICIENT_FUEL"
        end
    end

    -- Refuelling is an action with a result; read the tank again before allowing movement.
    local available = level
    if type(readFuel) == "function" then
        available = readFuel()
    end
    if available == "unlimited" then
        return true, "UNLIMITED_FUEL"
    end
    if type(available) ~= "number" or available < requiredFuel then
        return false, "INSUFFICIENT_FUEL"
    end

    return true, "FUEL_SAFE"
end

return FuelPolicy
