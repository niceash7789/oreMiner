local InventoryService = require("src.inventory.service")
local Pressure = require("src.inventory.pressure")
local defaults = require("src.config.defaults")

local count = 70
local selected = 6
local consolidationCalls = 0
local originalConsolidate = Pressure.consolidate
local originalReached = Pressure.reached
Pressure.consolidate = function(...)
    consolidationCalls = consolidationCalls + 1
    return originalConsolidate(...)
end
Pressure.reached = function(...)
    assert(consolidationCalls > 0, "pressure must be measured after consolidation")
    return originalReached(...)
end
local pose = { x = 0, y = -8, z = -13, facing = 1 }
local travelCalls = 0
local resupplyCalls = 0
local serviceStages = {}
local serviceMessages = {}
local rearChestChecks = 0
local rearChestAvailable = true
local serviceCheckpoints = {}
local currentProgress = { workUnitId = "surface-pair-1-main-1", nextAction = "mine_main_cell", floor = 0 }
local checkpoint = {
    setService = function(_, value, savedPose)
        serviceStages[#serviceStages + 1] = value and value.stage or "clear"
        serviceCheckpoints[#serviceCheckpoints + 1] = savedPose
            and { x = savedPose.x, y = savedPose.y, z = savedPose.z, facing = savedPose.facing }
        return true
    end,
}
local api = {
    getItemCount = function(slot) return slot == 2 and count or 0 end,
    getItemDetail = function(slot)
        if slot == 2 and count > 0 then return { name = "minecraft:cobblestone" } end
    end,
    getSelectedSlot = function() return selected end,
    select = function(slot) selected = slot return true end,
    transferTo = function() return false end,
    drop = function(amount) count = count - (amount or count); return true end,
    inspect = function()
        if pose.facing == 2 then
            rearChestChecks = rearChestChecks + 1
            if not rearChestAvailable then return false end
        end
        return true, { name = "minecraft:chest" }
    end,
}
local config = {
    inventory = { returnThreshold = 1 },
    base = {
        acceptedChestBlockIds = defaults.base.acceptedChestBlockIds,
        separateBulk = true,
    },
}
local service = InventoryService.new({
    turtle = api,
    config = config,
    itemConfig = defaults,
    pose = function() return pose end,
    checkpoint = function() return checkpoint end,
    progress = function() return currentProgress end,
    route = function() return {} end,
    configSnapshot = function() return {} end,
    turnToFacing = function(facing) pose.facing = facing; return true end,
    travel = function(target)
        travelCalls = travelCalls + 1
        pose.x, pose.y, pose.z, pose.facing = target.x, target.y, target.z, target.facing
        return true, "ROUTE_TARGET_REACHED"
    end,
    resupply = function(saved, route)
        assert(saved.x == 0 and saved.y == -8 and saved.z == -13 and saved.facing == 1)
        assert(type(route) == "table")
        resupplyCalls = resupplyCalls + 1
        return { ok = true, code = "RESUPPLY_COMPLETE" }
    end,
    safeForward = function() return true end,
    up = function() return true end,
    down = function() return true end,
    report = function(message) serviceMessages[#serviceMessages + 1] = message end,
    reportError = function(message) error(message) end,
})

assert(service.pressureReached(), "occupied-slot threshold should be evaluated by the service")
assert(consolidationCalls > 0, "pressure should consolidate before measuring occupied slots")
local serviced, serviceCode = service.serviceIfNeeded()
assert(serviced and serviceCode == "SERVICE_COMPLETE", "accepted chest should report completed service")
assert(count == 64, "configured cobblestone quota should remain after unload")
assert(selected == 6, "inventory service should restore the selected slot")
assert(pose.facing == 1, "inventory service should restore the saved facing")
assert(travelCalls == 2, "service must travel to home and back over its injected known route")
assert(rearChestChecks > 0, "enabled bulk routing must verify the rear chest before service travel")
assert(resupplyCalls == 1, "base service must resupply before resuming")
assert(table.concat(serviceStages, ",") == "returning,returning,at_base,unloading,at_base,resuming,resuming,clear",
    "service checkpoint should persist every stage and clear only after exact resume")
assert(serviceCheckpoints[1].y == -8 and serviceCheckpoints[1].z == -13
    and serviceCheckpoints[2].y == -8 and serviceCheckpoints[2].z == -13
    and serviceCheckpoints[3].x == 0 and serviceCheckpoints[3].y == 0 and serviceCheckpoints[3].z == 0
    and serviceCheckpoints[4].y == 0 and serviceCheckpoints[5].y == 0
    and serviceCheckpoints[6].y == 0 and serviceCheckpoints[7].y == 0
    and serviceCheckpoints[8].y == -8 and serviceCheckpoints[8].z == -13,
    "service snapshot must describe the known pose at each durable travel boundary")

-- Torch policy can request the same checkpointed service even when slot
-- pressure is low; this is used before the remaining torch stock is depleted.
local forcedService = service.serviceIfNeeded(true)
assert(forcedService and travelCalls == 4 and resupplyCalls == 2,
    "forced low-torch service must use the normal return, supply, and exact resume path")
local lowTorchMessageFound = false
for _, message in ipairs(serviceMessages) do
    if message:find("Low torch stock", 1, true) then lowTorchMessageFound = true end
end
assert(lowTorchMessageFound, "low-torch service must not be reported as inventory full")

local pressureServiceReported = InventoryService.new({
    turtle = api,
    config = { inventory = { returnThreshold = 1, autoConsolidate = false }, base = config.base },
    itemConfig = defaults,
    pose = function() return pose end,
    route = function() return {} end,
    turnToFacing = function(facing) pose.facing = facing; return true end,
    travel = function(target)
        pose.x, pose.y, pose.z, pose.facing = target.x, target.y, target.z, target.facing
        return true
    end,
    report = function(message) serviceMessages[#serviceMessages + 1] = message end,
    reportError = function() end,
})
local pressureMessageStart = #serviceMessages
pressureServiceReported.serviceIfNeeded()
local pressureMessageFound = false
for index = pressureMessageStart + 1, #serviceMessages do
    if serviceMessages[index]:find("Inventory pressure 1/1 slots", 1, true) then
        pressureMessageFound = true
    end
end
assert(pressureMessageFound,
    "pressure service must report occupied slots and configured threshold")

local recoveredPose = { x = 0, y = 0, z = 0, facing = 0 }
local recoveryStages = {}
local recoveryDestinations = {}
local recoveryTravel = {}
local recoveryTarget = { x = 0, y = -8, z = -13, facing = 1 }
local recoveryService = InventoryService.new({
    turtle = api,
    config = config,
    itemConfig = defaults,
    pose = function() return recoveredPose end,
    checkpoint = {
        setService = function(_, value)
            recoveryStages[#recoveryStages + 1] = value and value.stage or "clear"
            if value then
                recoveryDestinations[#recoveryDestinations + 1] = value.checkpoint
            end
            return true
        end,
    },
    progress = function() return currentProgress end,
    route = function() return {} end,
    configSnapshot = function() return {} end,
    turnToFacing = function(facing) recoveredPose.facing = facing; return true end,
    travel = function(target)
        recoveryTravel[#recoveryTravel + 1] = target
        recoveredPose.x, recoveredPose.y, recoveredPose.z, recoveredPose.facing =
            target.x, target.y, target.z, target.facing
        return true, "ROUTE_TARGET_REACHED"
    end,
    resupply = function(saved)
        assert(saved.x == recoveryTarget.x and saved.y == recoveryTarget.y
            and saved.z == recoveryTarget.z and saved.facing == recoveryTarget.facing,
            "resupply must budget the original checkpoint route")
        return { ok = true, code = "RESUPPLY_COMPLETE" }
    end,
    report = function() end,
    reportError = function(message) error(message) end,
})
local recovered, recoveryCode = recoveryService.resume(recoveryTarget)
assert(recovered and recoveryCode == "SERVICE_COMPLETE",
    "service recovery should finish from base and restore its saved mining pose")
assert(#recoveryTravel == 2 and recoveryTravel[1].y == 0
    and recoveryTravel[2].y == recoveryTarget.y
    and recoveredPose.x == recoveryTarget.x and recoveredPose.y == recoveryTarget.y
    and recoveredPose.z == recoveryTarget.z and recoveredPose.facing == recoveryTarget.facing,
    "service recovery must visit home then return to the exact saved pose")
assert(recoveryStages[1] == "returning" and recoveryStages[#recoveryStages] == "clear",
    "service recovery must preserve stage checkpoints and clear only after exact return")

-- A configured rear chest is verified after the turtle reaches base; it
-- cannot be inspected remotely from the mining checkpoint.
pose.x, pose.y, pose.z, pose.facing = 0, -8, -13, 1
local missingBulkTravel = 0
local missingBulkService = InventoryService.new({
    turtle = api,
    config = { inventory = { returnThreshold = 1 }, base = {
        supply = "left", primaryOutput = "right", bulkOutput = "back", separateBulk = true,
        acceptedChestBlockIds = defaults.base.acceptedChestBlockIds,
    } },
    itemConfig = defaults,
    pose = function() return pose end,
    checkpoint = checkpoint,
    progress = function() return currentProgress end,
    route = function() return {} end,
    configSnapshot = function() return {} end,
    turnToFacing = function(facing) pose.facing = facing; return true end,
    travel = function(target)
        missingBulkTravel = missingBulkTravel + 1
        pose.x, pose.y, pose.z, pose.facing = target.x, target.y, target.z, target.facing
        return true, "ROUTE_TARGET_REACHED"
    end,
    report = function() end,
    reportError = function() end,
})
rearChestAvailable = false
local missingBulkOk, missingBulkCode = missingBulkService.serviceIfNeeded(true)
assert(not missingBulkOk and missingBulkCode == "NO_BULK_CHEST"
    and missingBulkTravel == 1 and pose.x == 0 and pose.y == 0 and pose.z == 0
    and pose.facing == 0,
    "missing configured rear chest must stop at canonical base without replay: code="
        .. tostring(missingBulkCode) .. " trips=" .. tostring(missingBulkTravel)
        .. " pose=" .. tostring(pose.x) .. "," .. tostring(pose.y) .. ","
        .. tostring(pose.z) .. " f" .. tostring(pose.facing))
rearChestAvailable = true
assert(recoveryDestinations[1].y == recoveryTarget.y
    and recoveryDestinations[#recoveryDestinations].y == recoveryTarget.y,
    "service recovery must persist the original mining target before clearing the record")

-- Required base chests fail with side-specific errors while the turtle stays
-- at base and does not replay the mining route.
local function verifyMissingChest(expectedCode, absentFacing, separateBulk)
    local savedPose = { x = 0, y = -8, z = -13, facing = 1 }
    local chestPose = { x = 0, y = -8, z = -13, facing = 1 }
    local homeTravelCount = 0
    local missingApi = {
        getSelectedSlot = function() return 1 end,
        select = function() return true end,
        getItemCount = function() return 0 end,
        getItemDetail = function() return nil end,
        inspect = function()
            if chestPose.facing == absentFacing then return false end
            return true, { name = "minecraft:chest" }
        end,
    }
    local missingService = InventoryService.new({
        turtle = missingApi,
        config = { inventory = { returnThreshold = 1 }, base = {
            acceptedChestBlockIds = defaults.base.acceptedChestBlockIds,
            separateBulk = separateBulk,
        } },
        itemConfig = defaults,
        homeFacing = 1,
        pose = function() return chestPose end,
        turnToFacing = function(facing) chestPose.facing = facing; return true end,
        travel = function(target)
            homeTravelCount = homeTravelCount + 1
            chestPose.x, chestPose.y, chestPose.z, chestPose.facing =
                target.x, target.y, target.z, target.facing
            return true, "ROUTE_TARGET_REACHED"
        end,
        report = function() end,
        reportError = function() end,
    })
    local ok, code = missingService.serviceIfNeeded(true)
    assert(not ok and code == expectedCode, "missing chest should return " .. expectedCode)
    assert(homeTravelCount == 1 and chestPose.x == 0 and chestPose.y == 0
        and chestPose.z == 0 and chestPose.facing == 1,
        "missing chest should stop at canonical base without mining-route replay: trips="
            .. tostring(homeTravelCount) .. " pose=" .. tostring(chestPose.x) .. ","
            .. tostring(chestPose.y) .. "," .. tostring(chestPose.z) .. " f"
            .. tostring(chestPose.facing))
    assert(savedPose.y == -8, "fixture must begin at a mining checkpoint")
end

verifyMissingChest("NO_SUPPLY_CHEST", 0, false)
verifyMissingChest("NO_OUTPUT_CHEST", 2, false)
verifyMissingChest("NO_BULK_CHEST", 3, true)

-- A failed pre-departure checkpoint must prevent any route movement.
pose.x, pose.y, pose.z, pose.facing = 0, -8, -13, 1
count = 70
local departureTravelCalls = 0
local departureFailureService = InventoryService.new({
    turtle = api,
    config = config,
    itemConfig = defaults,
    pose = function() return pose end,
    checkpoint = { setService = function(_, value)
        if value and value.stage == "returning" then return false, "STATE_WRITE_FAILED" end
        return true
    end },
    progress = function() return currentProgress end,
    route = function() return {} end,
    configSnapshot = function() return {} end,
    turnToFacing = function(facing) pose.facing = facing; return true end,
    travel = function() departureTravelCalls = departureTravelCalls + 1; return true end,
    safeForward = function() return true end,
    up = function() return true end,
    down = function() return true end,
    report = function() end,
    reportError = function() end,
})
local departureSaved, departureCode = departureFailureService.serviceIfNeeded()
assert(not departureSaved and departureCode == "STATE_WRITE_FAILED" and departureTravelCalls == 0,
    "failed pre-departure checkpoint must stop before home travel")

-- If supplies are temporarily short, service remains at the verified base
-- pose with its durable stage intact; a later retry resumes the saved route.
pose.x, pose.y, pose.z, pose.facing = 0, -8, -13, 1
count = 70
local shortSupplyTravel = 0
local shortSupplyStage
local supplyAvailable = false
local torchFailureService = InventoryService.new({
    turtle = api,
    config = config,
    itemConfig = defaults,
    pose = function() return pose end,
    checkpoint = { setService = function(_, value)
        shortSupplyStage = value and value.stage or nil
        return true
    end },
    progress = function() return currentProgress end,
    route = function() return {} end,
    configSnapshot = function() return {} end,
    turnToFacing = function(facing) pose.facing = facing; return true end,
    travel = function(target)
        shortSupplyTravel = shortSupplyTravel + 1
        pose.x, pose.y, pose.z, pose.facing = target.x, target.y, target.z, target.facing
        return true, "ROUTE_TARGET_REACHED"
    end,
    resupply = function()
        return supplyAvailable and { ok = true, code = "RESUPPLY_COMPLETE" }
            or { ok = false, code = "NO_TORCHES" }
    end,
    report = function() end,
    reportError = function() end,
})
local torchSupplied, torchSupplyCode = torchFailureService.serviceIfNeeded(true)
assert(not torchSupplied and torchSupplyCode == "NO_TORCHES",
    "a temporary torch shortage must be reported for retry")
assert(shortSupplyTravel == 1 and pose.x == 0 and pose.y == 0 and pose.z == 0
    and shortSupplyStage == "at_base",
    "short supply must keep the durable service checkpoint at base")
supplyAvailable = true
local resumedAfterRestock = torchFailureService.resume({
    x = 0, y = -8, z = -13, facing = 1,
})
assert(resumedAfterRestock and shortSupplyTravel == 3 and shortSupplyStage == nil,
    "a later successful supply check must replay to the saved checkpoint and clear service")

-- A failed durable clear must not be hidden by a boolean fallback: otherwise
-- the next startup could mistake an uncleared service trip for normal mining.
pose.x, pose.y, pose.z, pose.facing = 0, -8, -13, 1
count = 70
local clearFailureCheckpoint = {
    setService = function(_, value)
        if value == nil then return false, "STATE_WRITE_FAILED" end
        return true
    end,
}
local clearFailureService = InventoryService.new({
    turtle = api,
    config = config,
    itemConfig = defaults,
    pose = function() return pose end,
    checkpoint = function() return clearFailureCheckpoint end,
    progress = function() return currentProgress end,
    route = function() return {} end,
    configSnapshot = function() return {} end,
    turnToFacing = function(facing) pose.facing = facing; return true end,
    travel = function(target)
        pose.x, pose.y, pose.z, pose.facing = target.x, target.y, target.z, target.facing
        return true, "ROUTE_TARGET_REACHED"
    end,
    safeForward = function() return true end,
    up = function() return true end,
    down = function() return true end,
    report = function() end,
    reportError = function() end,
})
local clearFailed, clearFailureCode = clearFailureService.serviceIfNeeded()
assert(not clearFailed and clearFailureCode == "STATE_WRITE_FAILED",
    "failed service checkpoint clear must be reported after return")

pose.x = 1
count = 70
local forwardCalls = 0
local failedFacingService = InventoryService.new({
    turtle = api,
    config = config,
    itemConfig = defaults,
    pose = function() return pose end,
    turnToFacing = function() return false end,
    travel = function(target)
        pose.x, pose.y, pose.z, pose.facing = target.x, target.y, target.z, target.facing
        return true, "ROUTE_TARGET_REACHED"
    end,
    safeForward = function() forwardCalls = forwardCalls + 1; return true end,
    up = function() return true end,
    down = function() return true end,
    report = function() end,
    reportError = function() end,
})
local failedService = failedFacingService.serviceIfNeeded()
assert(failedService == false, "service should stop when checked facing fails")
assert(forwardCalls == 0, "service must not move after a failed facing change")

-- With bulk separation disabled, every non-retained item is sent to the
-- verified right output chest; no rear chest is inspected or required.
local rightOutputDrops = 0
local rearInspections = 0
local mixedInventory = {
    [1] = { name = "minecraft:diamond_ore", count = 3 },
    [2] = { name = "mod:unknown_gem", count = 2 },
    [3] = { name = "minecraft:gravel", count = 5 },
    [4] = { name = "minecraft:cobblestone", count = 70 },
    [5] = { name = "minecraft:coal", count = 20 },
    [6] = { name = "minecraft:torch", count = 16 },
}
local mixedSelected = 8
local mixedApi = {
    getItemCount = function(slot)
        return mixedInventory[slot] and mixedInventory[slot].count or 0
    end,
    getItemDetail = function(slot)
        local item = mixedInventory[slot]
        return item and { name = item.name }
    end,
    getSelectedSlot = function() return mixedSelected end,
    select = function(slot) mixedSelected = slot; return true end,
    transferTo = function() return false end,
    drop = function(amount)
        local item = mixedInventory[mixedSelected]
        if not item then return false end
        local dropped = math.min(amount or item.count, item.count)
        item.count = item.count - dropped
        if pose.facing == 1 then rightOutputDrops = rightOutputDrops + dropped end
        return true
    end,
    inspect = function()
        if pose.facing == 2 then rearInspections = rearInspections + 1 end
        return true, { name = "minecraft:chest" }
    end,
}
pose.x, pose.y, pose.z, pose.facing = 0, -8, -13, 1
local rightOutputService = InventoryService.new({
    turtle = mixedApi,
    config = { inventory = { returnThreshold = 1 }, base = {
        acceptedChestBlockIds = defaults.base.acceptedChestBlockIds,
        separateBulk = false,
    } },
    itemConfig = defaults,
    pose = function() return pose end,
    turnToFacing = function(facing) pose.facing = facing; return true end,
    travel = function(target)
        pose.x, pose.y, pose.z, pose.facing = target.x, target.y, target.z, target.facing
        return true, "ROUTE_TARGET_REACHED"
    end,
    report = function() end,
    reportError = function(message) error(message) end,
})
local routedRight, routedRightCode = rightOutputService.serviceIfNeeded(true)
assert(routedRight and routedRightCode == "SERVICE_COMPLETE",
    "bulk-disabled service should complete through the right output chest")
assert(rightOutputDrops == 16,
    "ore, unknown, gravel, and excess cobblestone should all route right")
assert(mixedInventory[4].count == 64 and mixedInventory[5].count == 20
    and mixedInventory[6].count == 16,
    "service should preserve configured cobblestone, coal, and torch quotas")
assert(rearInspections == 0,
    "bulk-disabled service must not require or inspect a rear chest")
assert(mixedSelected == 8, "service should restore the selected slot")
assert(pose.x == 0 and pose.y == -8 and pose.z == -13 and pose.facing == 1,
    "service should return to the saved mining pose and facing")

-- A full primary output chest must leave the turtle at base and must not
-- replay the mining route with inventory still aboard.
local fullOutputInventory = {
    [1] = { name = "minecraft:diamond_ore", count = 3 },
    [2] = { name = "minecraft:cobblestone", count = 70 },
}
local fullOutputSelected = 9
local fullOutputDrops = 0
local fullOutputApi = {
    getItemCount = function(slot)
        return fullOutputInventory[slot] and fullOutputInventory[slot].count or 0
    end,
    getItemDetail = function(slot)
        local item = fullOutputInventory[slot]
        return item and { name = item.name }
    end,
    getSelectedSlot = function() return fullOutputSelected end,
    select = function(slot) fullOutputSelected = slot; return true end,
    transferTo = function() return false end,
    drop = function() fullOutputDrops = fullOutputDrops + 1; return false end,
    inspect = function() return true, { name = "minecraft:chest" } end,
}
pose.x, pose.y, pose.z, pose.facing = 0, -8, -13, 1
local fullOutputTravelCalls = 0
local fullOutputService = InventoryService.new({
    turtle = fullOutputApi,
    config = { inventory = { returnThreshold = 1 }, base = {
        acceptedChestBlockIds = defaults.base.acceptedChestBlockIds,
        separateBulk = false,
    } },
    itemConfig = defaults,
    pose = function() return pose end,
    turnToFacing = function(facing) pose.facing = facing; return true end,
    travel = function(target)
        fullOutputTravelCalls = fullOutputTravelCalls + 1
        pose.x, pose.y, pose.z, pose.facing = target.x, target.y, target.z, target.facing
        return true, "ROUTE_TARGET_REACHED"
    end,
    report = function() end,
    reportError = function() end,
})
local fullOutputOk, fullOutputCode = fullOutputService.serviceIfNeeded(true)
assert(not fullOutputOk and fullOutputCode == "UNLOAD_FAILED",
    "a rejected full output chest must fail inventory service")
assert(fullOutputTravelCalls == 1 and pose.x == 0 and pose.y == 0 and pose.z == 0,
    "service must stay at base instead of replaying the mining route")
assert(fullOutputDrops == 1 and fullOutputInventory[1].count == 3
    and fullOutputInventory[2].count == 70,
    "failed output acceptance must leave the carried items intact")
assert(fullOutputSelected == 9,
    "selected slot must be restored after output chest rejection")
Pressure.consolidate = originalConsolidate
Pressure.reached = originalReached

print("inventory service checks passed")
