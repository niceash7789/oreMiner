local Pressure = {}

function Pressure.occupiedSlots(turtleApi)
    local occupied = 0
    for slot = 1, 16 do
        if turtleApi.getItemCount(slot) > 0 then
            occupied = occupied + 1
        end
    end
    return occupied
end

function Pressure.reached(turtleApi, threshold)
    if type(threshold) ~= "number" or threshold < 1 or threshold > 16 then
        return false, {
            code = "INVALID_INVENTORY_THRESHOLD",
            message = "Inventory pressure threshold must be between 1 and 16.",
        }
    end

    local occupied = Pressure.occupiedSlots(turtleApi)
    return occupied >= threshold, occupied
end

return Pressure
