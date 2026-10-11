-- Inventory pressure, verified unloading, and return-trip coordination.
local Pressure = require("src.inventory.pressure")
local SlotGuard = require("src.inventory.slot_guard")
local Chest = require("src.inventory.chest")

local Service = {}

local function atPose(actual, expected)
    return type(actual) == "table"
        and actual.x == expected.x and actual.y == expected.y
        and actual.z == expected.z and actual.facing == expected.facing
end

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
        if result == nil or type(result) == "number" then return reached, result end
        deps.reportError(result.message)
        return true, nil
    end

    local function face(facing)
        if deps.turnToFacing(facing) ~= true then
            deps.reportError("Could not turn to the required facing.")
            return false, "POSITION_ERROR"
        end
        return true
    end

    local function verifyChest(facing, missingCode, failureFacing)
        local faced, faceCode = face(facing)
        if not faced then return false, faceCode end
        local hasBlock, block = deps.turtle.inspect()
        if not hasBlock or not block or not Chest.acceptsBlock(block.name, deps.config.base) then
            if failureFacing ~= nil then
                local restored, restoreCode = face(failureFacing)
                if not restored then return false, restoreCode end
            end
            return false, missingCode
        end
        return true
    end

    local function routeInventory(homeFacing)
        local guarded = SlotGuard.run(deps.turtle, function()
            local supplyOk, supplyCode = verifyChest(
                (homeFacing + 3) % 4, "NO_SUPPLY_CHEST", homeFacing)
            if not supplyOk then return { ok = false, code = supplyCode } end

            if deps.config.base.separateBulk == true then
                local bulkOk, bulkCode = verifyChest(
                    (homeFacing + 2) % 4, "NO_BULK_CHEST", homeFacing)
                if not bulkOk then return { ok = false, code = bulkCode } end
                local bulk = Chest.unloadBulk(deps.turtle, deps.itemConfig)
                if not bulk.ok then
                    return { ok = false, code = bulk.code == "CHEST_FULL" and "CHEST_FULL" or "UNLOAD_FAILED",
                        cause = bulk.code }
                end
            end

            local outputOk, outputCode = verifyChest(
                (homeFacing + 1) % 4, "NO_OUTPUT_CHEST", homeFacing)
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

    local function returnToStartAndUnload(resumeTarget, triggerReason)
        local pos = deps.pose()
        local saved = resumeTarget and {
            x = resumeTarget.x, y = resumeTarget.y,
            z = resumeTarget.z, facing = resumeTarget.facing,
        } or { x = pos.x, y = pos.y, z = pos.z, facing = pos.facing }
        local checkpoint = type(deps.checkpoint) == "function"
            and deps.checkpoint() or deps.checkpoint
        local progress = deps.progress and deps.progress()
        local function persist(stage, checkpointPose)
            if type(checkpoint) ~= "table" or type(progress) ~= "table" then
                return true
            end
            local ok, code = checkpoint:setService({
                stage = stage,
                checkpoint = checkpointPose or saved,
                resumeProgress = progress,
            }, deps.pose(), deps.route(), deps.configSnapshot())
            return ok, code
        end
        local savedService, saveCode = persist("returning")
        if not savedService then return false, saveCode or "STATE_WRITE_FAILED" end
        deps.report("[Inventory] " .. (triggerReason or "Service requested")
            .. " - returning to chests...")
        if type(deps.travel) ~= "function" then
            deps.reportError("Known-route inventory travel is unavailable.")
            return false, "RETURN_ROUTE_UNAVAILABLE"
        end
        local homeFacing = deps.homeFacing or 0
        local homePose = { x = 0, y = 0, z = 0, facing = homeFacing }
        savedService, saveCode = persist("returning", homePose)
        if not savedService then return false, saveCode or "STATE_WRITE_FAILED" end
        local travelled, travelCode = deps.travel(homePose)
        if not travelled or not atPose(deps.pose(), homePose) then
            deps.reportError("Could not return to surface over the recorded route.")
            return false, travelCode or "RETURN_ROUTE_FAILED"
        end

        savedService, saveCode = persist("at_base", homePose)
        if not savedService then return false, saveCode or "STATE_WRITE_FAILED" end

        savedService, saveCode = persist("unloading", homePose)
        if not savedService then return false, saveCode or "STATE_WRITE_FAILED" end
        local routed = routeInventory(homeFacing)
        if not routed.ok then
            deps.reportError("Inventory service failed (" .. routed.code .. ").")
            return false, routed.code
        end
        deps.report("[Inventory] Routed output; configured supply quotas preserved.")

        savedService, saveCode = persist("at_base", homePose)
        if not savedService then return false, saveCode or "STATE_WRITE_FAILED" end

        if type(deps.resupply) == "function" then
            local supplyOk, supplyCode = verifyChest(
                (homeFacing + 3) % 4, "NO_SUPPLY_CHEST", homeFacing)
            if not supplyOk then return false, supplyCode end
            local supplied = deps.resupply(saved, deps.route())
            if type(supplied) ~= "table" or supplied.ok ~= true then
                local code = type(supplied) == "table" and supplied.code or "RESUPPLY_FAILED"
                deps.reportError("Supply service failed (" .. tostring(code) .. ").")
                return false, code
            end
            local restored, restoreCode = face(homeFacing)
            if not restored then return false, restoreCode end
            deps.report("[Inventory] Fuel and torches verified for departure.")
        end

        savedService, saveCode = persist("resuming", homePose)
        if not savedService then return false, saveCode or "STATE_WRITE_FAILED" end
        savedService, saveCode = persist("resuming", saved)
        if not savedService then return false, saveCode or "STATE_WRITE_FAILED" end
        local returned, returnCode = deps.travel(saved)
        if not returned or not atPose(deps.pose(), saved) then
            deps.reportError("Could not return to the saved mining position over known route.")
            return false, returnCode or "RETURN_ROUTE_FAILED"
        end
        local cleared, clearCode = true, nil
        if checkpoint and type(progress) == "table" then
            cleared, clearCode = checkpoint:setService(nil, deps.pose(), deps.route(), deps.configSnapshot())
        end
        if not cleared then return false, clearCode or "STATE_WRITE_FAILED" end
        deps.report("[Inventory] Back at mining position.")
        return true
    end

    return {
        pressureReached = pressureReached,
        serviceIfNeeded = function(force)
            local triggerReason
            if force == true then
                triggerReason = "Low torch stock"
            else
                local reached, occupied = pressureReached()
                if not reached then return true end
                triggerReason = type(occupied) == "number"
                    and ("Inventory pressure " .. occupied .. "/"
                        .. tostring(deps.config.inventory.returnThreshold) .. " slots")
                    or "Inventory pressure check failed"
            end
            local serviced, code = returnToStartAndUnload(nil, triggerReason)
            if serviced then return true, "SERVICE_COMPLETE" end
            return false, code or "INVENTORY_SERVICE_FAILED"
        end,
        resume = function(savedTarget)
            if type(savedTarget) ~= "table" then return false, "INVALID_RESUME_TARGET" end
            local serviced, code = returnToStartAndUnload(savedTarget, "Resuming interrupted service")
            if serviced then return true, "SERVICE_COMPLETE" end
            return false, code or "INVENTORY_SERVICE_FAILED"
        end,
    }
end

return Service
