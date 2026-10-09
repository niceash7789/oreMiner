local Chest = {}
local ItemPolicy = require("src.config.item_policy")

local function contains(values, value)
    if type(values) ~= "table" or type(value) ~= "string" then
        return false
    end
    for _, candidate in ipairs(values) do
        if candidate == value then
            return true
        end
    end
    return false
end

function Chest.acceptsBlock(blockId, baseConfig)
    return contains(baseConfig and baseConfig.acceptedChestBlockIds, blockId)
end

-- A drop is complete only when the API confirms it and the selected slot is empty.
function Chest.dropSlot(turtleApi, slot)
    if type(turtleApi) ~= "table"
        or type(turtleApi.select) ~= "function"
        or type(turtleApi.getItemCount) ~= "function"
        or type(turtleApi.drop) ~= "function" then
        return { ok = false, code = "DROP_API_UNAVAILABLE" }
    end

    local before = turtleApi.getItemCount(slot)
    if type(before) ~= "number" or before < 0 then
        return { ok = false, code = "DROP_COUNT_UNAVAILABLE" }
    end
    if before == 0 then
        return { ok = true, code = "DROP_EMPTY" }
    end

    if turtleApi.select(slot) ~= true then
        return { ok = false, code = "DROP_SELECT_FAILED", remaining = before }
    end

    local apiSucceeded = turtleApi.drop()
    local after = turtleApi.getItemCount(slot)
    if type(after) ~= "number" or after < 0 then
        return { ok = false, code = "DROP_COUNT_UNAVAILABLE" }
    end
    if apiSucceeded ~= true then
        return { ok = false, code = "DROP_FAILED", remaining = after }
    end
    if after >= before then
        return { ok = false, code = "DROP_NOT_VERIFIED", remaining = after }
    end
    if after > 0 then
        return { ok = false, code = "CHEST_FULL", remaining = after }
    end

    return { ok = true, code = "DROP_COMPLETE", transferred = before - after }
end

-- Preserve item quotas across stacks and drop matching excess. The optional
-- predicate selects a destination class; omitted means the primary output and
-- therefore accepts every non-retained item.
function Chest.unload(turtleApi, itemConfig, shouldUnload)
    if type(turtleApi) ~= "table" or type(turtleApi.getItemCount) ~= "function"
        or type(turtleApi.getItemDetail) ~= "function" then
        return { ok = false, code = "UNLOAD_API_UNAVAILABLE" }
    end

    local counts = {}
    local itemIds = {}
    for slot = 1, 16 do
        local count = turtleApi.getItemCount(slot)
        if type(count) ~= "number" or count < 0 then
            return { ok = false, code = "UNLOAD_COUNT_UNAVAILABLE", slot = slot }
        end
        counts[slot] = count
        if count > 0 then
            local detail = turtleApi.getItemDetail(slot)
            local itemId = detail and detail.name
            if type(itemId) == "string" then
                itemIds[slot] = itemId
            end
        end
    end

    local retained = {}
    for slot = 1, 16 do
        if counts[slot] > 0 then
            local itemId = itemIds[slot]
            local quota = itemId and ItemPolicy.retainedCount(itemId, itemConfig) or counts[slot]
            local remainingQuota = math.max(0, quota - (retained[itemId] or 0))
            local keep = math.min(counts[slot], remainingQuota)
            if itemId then retained[itemId] = (retained[itemId] or 0) + keep end

            local dropCount = counts[slot] - keep
            local selectedForDestination = shouldUnload == nil
                or (itemId and shouldUnload(itemId) == true)
            if dropCount > 0 and selectedForDestination then
                local result = Chest.dropSlotCount(turtleApi, slot, dropCount)
                if not result.ok then return result end
            end
        end
    end
    return { ok = true, code = "UNLOAD_COMPLETE", retained = retained }
end


function Chest.unloadBulk(turtleApi, itemConfig)
    return Chest.unload(turtleApi, itemConfig, function(itemId)
        return ItemPolicy.isBulk(itemId, itemConfig)
    end)
end

-- Drop exactly the requested excess and verify the selected source count changed by that amount.
function Chest.dropSlotCount(turtleApi, slot, count)
    if type(turtleApi) ~= "table" or type(turtleApi.select) ~= "function"
        or type(turtleApi.getItemCount) ~= "function" or type(turtleApi.drop) ~= "function" then
        return { ok = false, code = "DROP_API_UNAVAILABLE" }
    end
    local before = turtleApi.getItemCount(slot)
    if type(before) ~= "number" or before < count or count < 1 then
        return { ok = false, code = "DROP_COUNT_UNAVAILABLE", slot = slot }
    end
    if turtleApi.select(slot) ~= true then
        return { ok = false, code = "DROP_SELECT_FAILED", remaining = before }
    end
    local apiSucceeded = turtleApi.drop(count)
    local after = turtleApi.getItemCount(slot)
    if type(after) ~= "number" or after < 0 then
        return { ok = false, code = "DROP_COUNT_UNAVAILABLE" }
    end
    if apiSucceeded ~= true then
        return { ok = false, code = "DROP_FAILED", remaining = after }
    end
    if after ~= before - count then
        return { ok = false, code = after > before - count and "CHEST_FULL" or "DROP_NOT_VERIFIED", remaining = after }
    end
    return { ok = true, code = "DROP_COMPLETE", transferred = count }
end

return Chest
