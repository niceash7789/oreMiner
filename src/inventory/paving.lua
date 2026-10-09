-- Optional floor paving over an already clear block.
local Paving = {}

function Paving.tryDown(config, turtleApi, slotGuard, itemPolicy)
    if type(config) ~= "table" or type(config.paving) ~= "table"
        or config.paving.enabled ~= true then
        return { ok = true, code = "PAVING_DISABLED", placed = false }
    end
    if turtleApi.detectDown() == true then
        return { ok = true, code = "PAVING_BLOCKED", placed = false }
    end

    local guarded = slotGuard.run(turtleApi, function()
        local totals = {}
        for slot = 1, 16 do
            local detail = turtleApi.getItemDetail(slot)
            if detail and type(detail.name) == "string" then
                totals[detail.name] = (totals[detail.name] or 0) + turtleApi.getItemCount(slot)
            end
        end
        for slot = 1, 16 do
            local detail = turtleApi.getItemDetail(slot)
            local available = detail and totals[detail.name] or 0
            if detail and itemPolicy.mayConsumeForPaving(detail.name, config, available)
                and turtleApi.select(slot) == true then
                if turtleApi.placeDown() == true then
                    return { placed = true, code = "PAVED" }
                end
                return { placed = false, code = "PAVING_PLACE_FAILED" }
            end
        end
        return { placed = false, code = "PAVING_MATERIAL_UNAVAILABLE" }
    end)
    if guarded.ok ~= true then
        return { ok = false, code = guarded.code or "PAVING_SLOT_RESTORE_FAILED", placed = false }
    end
    if type(guarded.value) ~= "table" then
        return { ok = false, code = "PAVING_OPERATION_FAILED", placed = false }
    end
    return { ok = true, code = guarded.value.code, placed = guarded.value.placed == true }
end

return Paving
