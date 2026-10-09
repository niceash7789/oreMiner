-- Verified, bounded branch-end ejection for excess cobblestone only.
local Chest = require("src.inventory.chest")
local ItemPolicy = require("src.config.item_policy")
local Pressure = require("src.inventory.pressure")
local SlotGuard = require("src.inventory.slot_guard")

local BranchEjection = {}

local function failure(cause, message)
    return {
        ok = false,
        code = "EJECT_FAILED",
        cause = cause,
        message = message or "Could not eject the complete cobblestone excess",
        retryable = false,
    }
end

local function totalCobblestone(turtleApi)
    local total = 0
    for slot = 1, 16 do
        local count = turtleApi.getItemCount(slot)
        if type(count) ~= "number" or count < 0 then return nil end
        if count > 0 then
            local detail = turtleApi.getItemDetail(slot)
            if detail and detail.name == "minecraft:cobblestone" then
                total = total + count
            end
        end
    end
    return total
end

function BranchEjection.run(turtleApi, itemConfig)
    if type(turtleApi) ~= "table" or type(turtleApi.getItemCount) ~= "function"
        or type(turtleApi.getItemDetail) ~= "function" then
        return failure("EJECT_API_UNAVAILABLE")
    end

    local guarded = SlotGuard.run(turtleApi, function()
        local consolidated = Pressure.consolidate(turtleApi)
        if not consolidated.ok then return failure(consolidated.code) end

        local before = totalCobblestone(turtleApi)
        if before == nil then return failure("EJECT_COUNT_UNAVAILABLE") end
        local reserve = ItemPolicy.retainedCount("minecraft:cobblestone", itemConfig)
        local remaining = math.max(0, before - reserve)
        local requested = remaining

        for slot = 16, 1, -1 do
            if remaining == 0 then break end
            local detail = turtleApi.getItemDetail(slot)
            if detail and detail.name == "minecraft:cobblestone" then
                local count = turtleApi.getItemCount(slot)
                local amount = math.min(count, remaining)
                if amount > 0 then
                    local dropped = Chest.dropSlotCount(turtleApi, slot, amount)
                    if not dropped.ok then return failure(dropped.code) end
                    remaining = remaining - amount
                end
            end
        end

        local after = totalCobblestone(turtleApi)
        if after == nil or remaining ~= 0 or before - after ~= requested then
            return failure("EJECT_NOT_VERIFIED")
        end
        return { ok = true, code = requested > 0 and "EJECT_COMPLETE" or "EJECT_NOT_NEEDED",
            ejected = requested, retained = after }
    end)

    if not guarded.ok then return failure(guarded.code, guarded.message) end
    return guarded.value
end

return BranchEjection
