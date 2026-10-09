local Pressure = {}
local SlotGuard = require("src.inventory.slot_guard")

local function readCount(turtleApi, slot)
    local count = turtleApi.getItemCount(slot)
    if type(count) ~= "number" or count < 0 then
        error("could not read inventory slot count")
    end
    return count
end

function Pressure.slotCounts(turtleApi)
    local occupied = 0
    for slot = 1, 16 do
        if turtleApi.getItemCount(slot) > 0 then
            occupied = occupied + 1
        end
    end
    return occupied, 16 - occupied
end

function Pressure.occupiedSlots(turtleApi)
    local occupied = Pressure.slotCounts(turtleApi)
    return occupied
end

function Pressure.reached(turtleApi, threshold)
    if type(threshold) ~= "number" or threshold ~= math.floor(threshold) or threshold < 1 or threshold > 15 then
        return false, {
            code = "INVALID_INVENTORY_THRESHOLD",
            message = "Inventory pressure threshold must be between 1 and 16.",
        }
    end

    local occupied = Pressure.occupiedSlots(turtleApi)
    return occupied >= threshold, occupied
end

-- Merge compatible stacks opportunistically. Item names identify candidates only;
-- transferTo's observed count deltas determine whether a pair was compatible.
function Pressure.consolidate(turtleApi)
    if type(turtleApi) ~= "table"
        or type(turtleApi.getItemCount) ~= "function"
        or type(turtleApi.getItemDetail) ~= "function"
        or type(turtleApi.getSelectedSlot) ~= "function"
        or type(turtleApi.select) ~= "function"
        or type(turtleApi.transferTo) ~= "function" then
        return { ok = false, code = "INVALID_ARGUMENT", message = "inventory transfer API is required" }
    end

    local guarded = SlotGuard.run(turtleApi, function()
        local movedTotal = 0
        for targetSlot = 1, 16 do
            local targetBefore = readCount(turtleApi, targetSlot)
            local targetDetail = targetBefore > 0 and turtleApi.getItemDetail(targetSlot) or nil
            if targetDetail and type(targetDetail.name) == "string" then
                for sourceSlot = targetSlot + 1, 16 do
                    local sourceBefore = readCount(turtleApi, sourceSlot)
                    local sourceDetail = sourceBefore > 0 and turtleApi.getItemDetail(sourceSlot) or nil
                    if sourceDetail and sourceDetail.name == targetDetail.name then
                        assert(turtleApi.select(sourceSlot) == true, "could not select source slot")
                        turtleApi.transferTo(targetSlot)
                        local sourceAfter = readCount(turtleApi, sourceSlot)
                        local targetAfter = readCount(turtleApi, targetSlot)
                        local sourceDelta = sourceBefore - sourceAfter
                        local targetDelta = targetAfter - targetBefore
                        if sourceDelta < 0 or targetDelta < 0 or sourceDelta ~= targetDelta then
                            error("inventory transfer count deltas did not match")
                        end
                        movedTotal = movedTotal + sourceDelta
                        targetBefore = targetAfter
                    end
                end
            end
        end
        return movedTotal
    end)

    if not guarded.ok then return guarded end
    return { ok = true, transferred = guarded.value }
end

return Pressure
