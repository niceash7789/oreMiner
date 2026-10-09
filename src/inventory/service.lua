-- Inventory pressure, verified unloading, and return-trip coordination.
local Pressure = require("src.inventory.pressure")
local SlotGuard = require("src.inventory.slot_guard")
local Chest = require("src.inventory.chest")

local Service = {}

function Service.new(deps)
    local function pressureReached()
        if deps.config.inventory.autoConsolidate ~= false then
            local consolidated = Pressure.consolidate(deps.turtle)
            if not consolidated.ok then
                deps.reportError("Inventory consolidation failed (" .. consolidated.code .. ").")
            end
        end
        local reached, result = Pressure.reached(
            deps.turtle,
            deps.config.inventory.returnThreshold
        )
        if result == nil or type(result) == "number" then return reached end
        deps.reportError(result.message)
        return true
    end

    local function face(facing)
        if deps.turnToFacing(facing) ~= true then
            deps.reportError("Could not turn to the required facing.")
            return false, "POSITION_ERROR"
        end
        return true
    end

    local function verifyChest(facing, missingCode)
        local faced, faceCode = face(facing)
        if not faced then return false, faceCode end
        local hasBlock, block = deps.turtle.inspect()
        if not hasBlock or not block or not Chest.acceptsBlock(block.name, deps.config.base) then
            return false, missingCode
        end
        return true
    end

    local function routeInventory(homeFacing)
        local guarded = SlotGuard.run(deps.turtle, function()
            local supplyOk, supplyCode = verifyChest((homeFacing + 3) % 4, "NO_SUPPLY_CHEST")
            if not supplyOk then return { ok = false, code = supplyCode } end

            if deps.config.base.separateBulk == true then
                local bulkOk, bulkCode = verifyChest((homeFacing + 2) % 4, "NO_BULK_CHEST")
                if not bulkOk then return { ok = false, code = bulkCode } end
                local bulk = Chest.unloadBulk(deps.turtle, deps.itemConfig)
                if not bulk.ok then
                    return { ok = false, code = bulk.code == "CHEST_FULL" and "CHEST_FULL" or "UNLOAD_FAILED",
                        cause = bulk.code }
                end
            end

            local outputOk, outputCode = verifyChest((homeFacing + 1) % 4, "NO_OUTPUT_CHEST")
            if not outputOk then return { ok = false, code = outputCode } end
            local output = Chest.unload(deps.turtle, deps.itemConfig)
            if not output.ok then
                return { ok = false, code = output.code == "CHEST_FULL" and "CHEST_FULL" or "UNLOAD_FAILED",
                    cause = output.code }
            end

            local restored, restoreCode = face(homeFacing)
            if not restored then return { ok = false, code = restoreCode } end
            return { ok = true, code = "UNLOAD_COMPLETE" }
        end)
        if not guarded.ok then return { ok = false, code = "UNLOAD_FAILED", cause = guarded.code } end
        return guarded.value
    end

    local function returnToStartAndUnload()
        local pos = deps.pose()
        local saved = { x = pos.x, y = pos.y, z = pos.z, facing = pos.facing }
        deps.report("[Inventory] Full - returning to chest...")

        while pos.y > 0 do
            if not deps.down() then deps.reportError("Could not move down for unload trip."); return false end
            pos = deps.pose()
        end
        while pos.y < 0 do
            if not deps.up() then deps.reportError("Could not move up for unload trip."); return false end
            pos = deps.pose()
        end

        if pos.x > 0 then
            if not face(3) then return false end
            while deps.pose().x > 0 do
                if not deps.safeForward() then deps.reportError("Could not return to main tunnel."); return false end
            end
        elseif pos.x < 0 then
            if not face(1) then return false end
            while deps.pose().x < 0 do
                if not deps.safeForward() then deps.reportError("Could not return to main tunnel."); return false end
            end
        end

        pos = deps.pose()
        if pos.z < 0 then
            if not face(2) then return false end
            while deps.pose().z < 0 do
                if not deps.safeForward() then deps.reportError("Could not return to start."); return false end
            end
        elseif pos.z > 0 then
            if not face(0) then return false end
            while deps.pose().z > 0 do
                if not deps.safeForward() then deps.reportError("Could not return to start."); return false end
            end
        end

        local homeFacing = deps.homeFacing or 0
        local routed = routeInventory(homeFacing)
        if not routed.ok then
            deps.reportError("Inventory service failed (" .. routed.code .. ").")
            return false, routed.code
        end
        deps.report("[Inventory] Routed output; configured supply quotas preserved.")

        if saved.z < 0 then
            if not face(0) then return false, "POSITION_ERROR" end
            while deps.pose().z > saved.z do
                if not deps.safeForward() then deps.reportError("Could not return to mining position."); return false end
            end
        elseif saved.z > 0 then
            if not face(2) then return false, "POSITION_ERROR" end
            while deps.pose().z < saved.z do
                if not deps.safeForward() then deps.reportError("Could not return to mining position."); return false end
            end
        end
        if saved.x > 0 then
            if not face(1) then return false, "POSITION_ERROR" end
            while deps.pose().x < saved.x do
                if not deps.safeForward() then deps.reportError("Could not return to branch position."); return false end
            end
        elseif saved.x < 0 then
            if not face(3) then return false, "POSITION_ERROR" end
            while deps.pose().x > saved.x do
                if not deps.safeForward() then deps.reportError("Could not return to branch position."); return false end
            end
        end
        pos = deps.pose()
        while pos.y < saved.y do
            if not deps.up() then deps.reportError("Could not restore mining height."); return false end
            pos = deps.pose()
        end
        while pos.y > saved.y do
            if not deps.down() then deps.reportError("Could not restore mining height."); return false end
            pos = deps.pose()
        end
        if not face(saved.facing) then return false, "POSITION_ERROR" end
        deps.report("[Inventory] Back at mining position.")
        return true
    end

    return {
        pressureReached = pressureReached,
        serviceIfNeeded = function()
            if not pressureReached() then return true end
            local serviced, code = returnToStartAndUnload()
            if serviced then return true, "SERVICE_COMPLETE" end
            return false, code or "INVENTORY_SERVICE_FAILED"
        end,
    }
end

return Service
