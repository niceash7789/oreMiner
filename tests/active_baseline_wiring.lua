local Pose = require("src.navigation.pose")
local SlotGuard = require("src.inventory.slot_guard")
local ItemPolicy = require("src.config.item_policy")
local defaults = require("src.config.defaults")
local fileConfig = require("tests.config_fixture")

local poseMoves = 0
local guardedOperations = 0
local pavingChecks = 0

local originalAfterMove = Pose.afterMove
local originalGuardRun = SlotGuard.run
local originalIsPaving = ItemPolicy.isPaving
local originalPavingItems = defaults.paving.allowedItems
local originalPavingEnabled = defaults.paving.enabled
local originalRetainedCount = defaults.paving.retainedCount
local originalPavingProtected = defaults.paving.protectedItems
local originalPavingIsPaving = defaults.paving.isPaving
local originalBranchLength = fileConfig.mining.branchLength
local originalBranchPairs = fileConfig.mining.branchPairs
local originalBranchSpacing = fileConfig.mining.branchSpacing
local originalFloorCount = fileConfig.mining.floorCount
local originalFeaturePaving = fileConfig.features.paving
local originalOreEnabled = fileConfig.ore.enabled
local originalTunnelInterval = fileConfig.lighting.tunnelInterval
local originalFeaturesTorches = fileConfig.features.torches
local originalLightingEnabled = fileConfig.lighting.enabled

Pose.afterMove = function(...)
    poseMoves = poseMoves + 1
    return originalAfterMove(...)
end

SlotGuard.run = function(...)
    guardedOperations = guardedOperations + 1
    return originalGuardRun(...)
end

ItemPolicy.isPaving = function(...)
    pavingChecks = pavingChecks + 1
    return originalIsPaving(...)
end

defaults.paving.enabled = true
defaults.paving.retainedCount = 0
defaults.paving.allowedItems = { "test:paver" }
defaults.paving.protectedItems = { "minecraft:coal", "minecraft:torch" }
defaults.paving.isPaving = true
fileConfig.mining.branchLength = 1
fileConfig.mining.branchPairs = 1
fileConfig.mining.branchSpacing = 3
fileConfig.mining.floorCount = 4
fileConfig.lighting.tunnelInterval = 1
fileConfig.features.torches = true
fileConfig.lighting.enabled = true
fileConfig.features.paving = false
fileConfig.ore.enabled = false
local activeConfig = require("src.config.item_policy")
local originalMayConsume = activeConfig.mayConsumeForPaving
local originalPolicyIsPaving = activeConfig.isPaving

local selectedSlot = 5
local pavingCount = 16
local coalCount = 64
local placements = 0
local torchPlacementFrames = {}
local torchNicheReady = false
local torchNicheDigs = 0
local failedTorchPlace = false
local upperObstructionPresent = true
local upperObstructionDigs = 0
local upperBlockedMoves = 0
local rearObstructionPresent = true
local rearClearFacing
local rearObstructionDigs = 0
local aboveObstructionPresent = false
local aboveInjected = false
local aboveObstructionDigs = 0
local belowObstructionPresent = false
local belowInjected = false
local belowObstructionDigs = 0
local world = { x = 0, y = 0, z = 0, facing = 0 }
local persistedFiles = {}
local physicalActionProgress = {}
local firstShaftStart
local firstMainTunnelTrace = {}
local firstMainTunnelBackMoves = 0

local function recordPhysicalAction(kind, direction)
    local raw = persistedFiles["oreMiner/state.json"]
    assert(raw, "physical actions require an active durable snapshot")
    local state = assert(load("return " .. raw))()
    assert(state.pendingAction and state.pendingAction.kind == kind
        and state.pendingAction.direction == direction,
        "physical action intent must be durable before the turtle API")
    assert(state.progress and state.progress.workUnitId,
        "physical actions require a durable logical cursor")
    physicalActionProgress[#physicalActionProgress + 1] = state.progress
    if kind == "move" and state.service == nil and state.progress.phase == "main_shaft"
        and state.progress.floor == 1 and state.progress.branchPair == 1 then
        if direction == "forward" then
            firstMainTunnelTrace[#firstMainTunnelTrace + 1] = {
                cursorOffset = state.progress.offset, x = world.x,
            }
        elseif direction == "back" then
            firstMainTunnelBackMoves = firstMainTunnelBackMoves + 1
        end
    end
    if not firstShaftStart and kind == "move" and direction == "forward"
        and state.progress.phase == "branch_outbound_lower"
        and state.progress.branchPair == 1 and state.progress.side == "left"
        and state.progress.offset == 0 then
        firstShaftStart = {
            x = world.x, y = world.y, z = world.z, facing = world.facing,
        }
    end
end

local function translateForward()
    if world.facing == 0 then
        world.z = world.z - 1
    elseif world.facing == 1 then
        world.x = world.x + 1
    elseif world.facing == 2 then
        world.z = world.z + 1
    else
        world.x = world.x - 1
    end
    return true
end

local turtleApi = {
    getFuelLevel = function() return "unlimited" end,
    getSelectedSlot = function() return selectedSlot end,
    select = function(slot) selectedSlot = slot return true end,
    getItemCount = function(slot)
        if slot == 2 then return pavingCount end
        if slot == 3 then return 64 end
        if slot == 4 then return coalCount end
        return 0
    end,
    getItemDetail = function(slot)
        if slot == 2 and pavingCount > 0 then
            return { name = "test:paver" }
        end
        if slot == 3 then return { name = "minecraft:torch" } end
        if slot == 4 and coalCount > 0 then return { name = "minecraft:coal" } end
        return nil
    end,
    refuel = function() return false end,
    forward = function()
        recordPhysicalAction("move", "forward")
        local state = assert(load("return " .. persistedFiles["oreMiner/state.json"]))()
        local progress = state.progress
        if progress.phase == "branch_upper_return"
            and progress.side == "left" and upperObstructionPresent then
            upperBlockedMoves = upperBlockedMoves + 1
            return false
        end
        return translateForward()
    end,
    back = function()
        recordPhysicalAction("move", "back")
        if rearObstructionPresent then
            rearClearFacing = (world.facing + 2) % 4
            return false
        end
        world.facing = (world.facing + 2) % 4
        translateForward()
        world.facing = (world.facing + 2) % 4
        return true
    end,
    up = function()
        recordPhysicalAction("move", "up")
        if not aboveInjected then aboveInjected, aboveObstructionPresent = true, true end
        if aboveObstructionPresent then return false end
        world.y = world.y + 1
        return true
    end,
    down = function()
        recordPhysicalAction("move", "down")
        if not belowInjected then belowInjected, belowObstructionPresent = true, true end
        if belowObstructionPresent then return false end
        world.y = world.y - 1
        return true
    end,
    turnLeft = function()
        recordPhysicalAction("turn", "left")
        world.facing = (world.facing - 1) % 4
        return true
    end,
    turnRight = function()
        recordPhysicalAction("turn", "right")
        world.facing = (world.facing + 1) % 4
        return true
    end,
    detect = function()
        if rearObstructionPresent and rearClearFacing == world.facing then return true end
        local raw = persistedFiles["oreMiner/state.json"]
        local progress = raw and assert(load("return " .. raw))().progress
        if progress and progress.phase == "branch_upper_return"
            and progress.side == "left" then
            return upperObstructionPresent
        end
        if selectedSlot == 3 then
            local nicheFacing = progress and (progress.phase == "main_shaft" and 2
                or progress.phase == "branch_outbound_lower"
                    and (progress.side == "left" and 1 or 3))
            if nicheFacing == world.facing then
                return not torchNicheReady
            end
        end
        return false
    end,
    detectUp = function() return aboveObstructionPresent end,
    detectDown = function() return belowObstructionPresent end,
    dig = function()
        if rearObstructionPresent and rearClearFacing == world.facing then
            recordPhysicalAction("dig", "forward")
            rearObstructionPresent = false
            rearObstructionDigs = rearObstructionDigs + 1
            return true
        end
        local raw = persistedFiles["oreMiner/state.json"]
        local progress = raw and assert(load("return " .. raw))().progress
        if progress and progress.phase == "branch_upper_return"
            and progress.side == "left"
            and upperObstructionPresent then
            recordPhysicalAction("dig", "forward")
            upperObstructionPresent = false
            upperObstructionDigs = upperObstructionDigs + 1
            return true
        end
        if selectedSlot == 3 then
            recordPhysicalAction("dig", "forward")
            torchNicheReady = true
            torchNicheDigs = torchNicheDigs + 1
            return true
        end
        return false
    end,
    digUp = function()
        if aboveObstructionPresent then
            recordPhysicalAction("dig", "up")
            aboveObstructionPresent = false
            aboveObstructionDigs = aboveObstructionDigs + 1
            return true
        end
        return false
    end,
    digDown = function()
        if belowObstructionPresent then
            recordPhysicalAction("dig", "down")
            belowObstructionPresent = false
            belowObstructionDigs = belowObstructionDigs + 1
            return true
        end
        return false
    end,
    attack = function() return false end,
    inspect = function()
        if rearObstructionPresent and rearClearFacing == world.facing then
            return true, { name = "minecraft:stone" }
        end
        if upperObstructionPresent then
            local raw = persistedFiles["oreMiner/state.json"]
            local progress = raw and assert(load("return " .. raw))().progress
            if progress and progress.phase == "branch_upper_return"
                and progress.side == "left" then
                return true, { name = "minecraft:stone" }
            end
        end
        if selectedSlot == 3 then
            local raw = persistedFiles["oreMiner/state.json"]
            local progress = raw and assert(load("return " .. raw))().progress
            local nicheFacing = progress and (progress.phase == "main_shaft" and 2
                or progress.phase == "branch_outbound_lower"
                    and (progress.side == "left" and 1 or 3))
            if nicheFacing == world.facing and not torchNicheReady then
                return true, { name = "minecraft:stone" }
            end
        end
        if world.x == 0 and world.y == 0 and world.z == 0 and world.facing == 3 then
            return true, { name = "minecraft:chest" }
        end
        return false
    end,
    inspectUp = function()
        if aboveObstructionPresent then return true, { name = "minecraft:stone" } end
        return false
    end,
    inspectDown = function()
        if belowObstructionPresent then return true, { name = "minecraft:stone" } end
        return false
    end,
    placeDown = function()
        if selectedSlot ~= 2 or pavingCount < 1 then
            return false
        end
        pavingCount = pavingCount - 1
        placements = placements + 1
        return true
    end,
    place = function()
        if selectedSlot == 3 then
            local savedState = persistedFiles["oreMiner/state.json"]
            local progress = savedState and assert(load("return " .. savedState))().progress
            if not failedTorchPlace and progress and progress.floor == 2
                and progress.phase == "branch_outbound_lower"
                and progress.side == "left" then
                failedTorchPlace = true
                torchNicheReady = false
                return false
            end
            torchPlacementFrames[#torchPlacementFrames + 1] = {
                x = world.x, y = world.y, z = world.z, facing = world.facing,
                progress = progress,
            }
            torchNicheReady = false
            return true
        end
        return false
    end,
    transferTo = function() return true end,
    suck = function() return false end,
    drop = function() return true end,
}

local inputs = { "y" }
local inputIndex = 0
local output = {}
local failedOneReport = false
local environment = {}
for key, value in pairs(_G) do
    environment[key] = value
end
environment.turtle = turtleApi
environment.require = function(name)
    if name == "config" then return fileConfig end
    return require(name)
end
environment.fs = {
    exists = function(path) return persistedFiles[path] ~= nil end,
    makeDir = function() end,
    combine = function(left, right) return left .. "/" .. right end,
    open = function(path, mode)
        if mode == "r" then
            if persistedFiles[path] == nil then return nil end
            local content = persistedFiles[path]
            return { readAll = function() return content end, close = function() end }
        end
        local content = ""
        return {
            write = function(value) content = content .. value end,
            close = function() persistedFiles[path] = content end,
        }
    end,
    delete = function(path) persistedFiles[path] = nil end,
    move = function(source, target) persistedFiles[target], persistedFiles[source] = persistedFiles[source], nil end,
}
local function serialize(value)
    if type(value) == "table" then
        local entries = {}
        for key, child in pairs(value) do
            local renderedKey = type(key) == "string" and "[" .. string.format("%q", key) .. "]" or "[" .. tostring(key) .. "]"
            entries[#entries + 1] = renderedKey .. "=" .. serialize(child)
        end
        return "{" .. table.concat(entries, ",") .. "}"
    end
    if type(value) == "string" then return string.format("%q", value) end
    return tostring(value)
end

environment.textutils = {
    serialize = serialize,
    serializeJSON = serialize,
    unserialize = function(value) return load("return " .. value)() end,
    unserializeJSON = function(value) return load("return " .. value)() end,
}
environment.sleep = function() end
environment.os = {}
for key, value in pairs(os) do environment.os[key] = value end
environment.os.epoch = function() return 0 end
environment.write = function() end
environment.read = function()
    inputIndex = inputIndex + 1
    return inputs[inputIndex]
end
environment.print = function(...)
    if not failedOneReport then
        failedOneReport = true
        error("simulated terminal failure")
    end
    local values = {}
    for index = 1, select("#", ...) do
        values[index] = tostring(select(index, ...))
    end
    output[#output + 1] = table.concat(values, " ")
end

local chunk, loadError = loadfile("src/branch_miner.lua", "t", environment)
assert(chunk, loadError)
local ok, runtimeError = pcall(chunk)

Pose.afterMove = originalAfterMove
SlotGuard.run = originalGuardRun
ItemPolicy.isPaving = originalIsPaving
defaults.paving.allowedItems = originalPavingItems
defaults.paving.enabled = originalPavingEnabled
defaults.paving.retainedCount = originalRetainedCount
defaults.paving.protectedItems = originalPavingProtected
defaults.paving.isPaving = originalPavingIsPaving
fileConfig.mining.branchLength = originalBranchLength
fileConfig.mining.branchPairs = originalBranchPairs
fileConfig.mining.branchSpacing = originalBranchSpacing
fileConfig.mining.floorCount = originalFloorCount
fileConfig.lighting.tunnelInterval = originalTunnelInterval
fileConfig.features.torches = originalFeaturesTorches
fileConfig.lighting.enabled = originalLightingEnabled
fileConfig.features.paving = originalFeaturePaving
fileConfig.ore.enabled = originalOreEnabled
activeConfig.mayConsumeForPaving = originalMayConsume
activeConfig.isPaving = originalPolicyIsPaving

assert(ok, runtimeError)
local upperTrace = {}
for _, progress in ipairs(physicalActionProgress) do
    if progress.phase == "branch_upper_return" then
        upperTrace[#upperTrace + 1] = tostring(progress.side) .. ":" .. tostring(progress.floor)
    end
end
assert(upperBlockedMoves == 1 and upperObstructionDigs == 1
    and not upperObstructionPresent,
    "upper branch sweep should dig one blocking block and retry its saved forward edge: "
        .. tostring(upperBlockedMoves) .. "/" .. tostring(upperObstructionDigs)
        .. " cursors=" .. table.concat(upperTrace, ",")
        .. " output=" .. table.concat(output, " | "))
assert(rearObstructionDigs == 1 and aboveObstructionDigs == 1
    and belowObstructionDigs == 1,
    "back, up, and down moves should each clear and retry a blocked planned edge")
assert(failedOneReport, "the test should inject an optional reporting failure")
assert(ok, runtimeError)
assert(guardedOperations > 0, "inventory pressure should consolidate through the slot guard: "
    .. tostring(output[#output]))
assert(pavingChecks == 0, "disabled default paving should not classify items")
assert(placements == 0, "disabled default paving should not place blocks")
local leftShaftTorch, rightShaftTorch = false, false
local stairTorchInsidePassage = false
for _, torchPose in ipairs(torchPlacementFrames) do
    if torchPose.y == -8 and torchPose.facing == 1 then leftShaftTorch = true end
    if torchPose.y == -8 and torchPose.facing == 3 then rightShaftTorch = true end
    if torchPose.x == 0 and torchPose.y == -3 and torchPose.z == -8
        and torchPose.facing == 1 and torchPose.progress
        and torchPose.progress.phase == "stairs" then
        stairTorchInsidePassage = true
    end
end
assert(leftShaftTorch and rightShaftTorch,
    "each shaft should place at its scheduled outbound cell facing its route-defined right wall")
assert(torchNicheDigs >= 2,
    "floor tunnel torches should carve their right-wall niche before placement")
assert(failedTorchPlace, "the fixture should exercise a failed branch torch placement")
local warnedAboutTorch = false
for _, line in ipairs(output) do
    if line:find("WARNING: Skipped right-wall torch", 1, true) then
        warnedAboutTorch = true
        break
    end
end
assert(warnedAboutTorch, "failed branch torch placement should warn and keep mining")
assert(firstShaftStart and firstShaftStart.x == 3 and firstShaftStart.y == -8
    and firstShaftStart.z == -13 and firstShaftStart.facing == 0,
    "the first shaft should start three blocks along the perpendicular main tunnel")
assert(#firstMainTunnelTrace == 3 and firstMainTunnelBackMoves == 0
    and firstMainTunnelTrace[1].cursorOffset == 0 and firstMainTunnelTrace[1].x == 0
    and firstMainTunnelTrace[2].cursorOffset == 1 and firstMainTunnelTrace[2].x == 1
    and firstMainTunnelTrace[3].cursorOffset == 2 and firstMainTunnelTrace[3].x == 2,
    "the first main tunnel must advance continuously for three cells before its shaft")
local torchLocations = {}
for _, frame in ipairs(torchPlacementFrames) do
    torchLocations[#torchLocations + 1] = string.format("(%d,%d,%d,%d:%s)",
        frame.x, frame.y, frame.z, frame.facing,
        frame.progress and frame.progress.phase or "none")
end
assert(stairTorchInsidePassage,
    "stair torches should place into the cleared passage without a niche: "
        .. table.concat(torchLocations, ", "))
assert(selectedSlot == 5, "active helpers should restore the original selected slot")
-- A completed baseline job now follows recorded cleared edges home and restores
-- its original surface facing before reporting success.
assert(world.x == 0 and world.y == 0 and world.z == 0 and world.facing == 0,
    "short branch pair should return to the exact origin pose")
local finalState = assert(load("return " .. assert(persistedFiles["oreMiner/state.json"]))())
assert(finalState.status == "complete", "the multi-floor run should commit completion at surface origin")
assert(not finalState.lighting.placed["floor-2-left-shaft-3-1"],
    "failed branch torch placement must not be committed to the lighting ledger")
assert(finalState.floorLandings[1].landing.y == -8
    and finalState.floorLandings[1].landing.z == -13,
    "floor 1 landing should be saved at the specified depth and offset")
assert(finalState.floorLandings[4].landing.y == -32
    and finalState.floorLandings[4].landing.z == -43,
    "floor 4 landing should be saved at the configured depth and offset")
assert(finalState.progress.floor == 4,
    "the durable mining cursor should retain the active floor identity")
assert(finalState.progress.phase == "floor_complete"
    and finalState.progress.nextAction == "advance_floor",
    "the last floor must commit completion only after restoring its landing")
assert(finalState.progress.completionStatus == "complete",
    "the terminal work unit must persist its completion status")

local seenCursor = {}
for _, progress in ipairs(physicalActionProgress) do
    seenCursor[progress.phase .. ":" .. progress.side .. ":" .. progress.nextAction] = true
end
assert(seenCursor["main_shaft:none:mine_main_cell"],
    "main-shaft movement should carry its saved logical cursor")
assert(seenCursor["branch_outbound_lower:left:mine_branch_cell"]
    and seenCursor["branch_outbound_lower:right:mine_branch_cell"],
    "both outbound branches should carry their saved logical cursor")
assert(seenCursor["branch_upper_return:left:scan_and_return_branch_cell"]
    and seenCursor["branch_upper_return:right:scan_and_return_branch_cell"],
    "both upper returns should carry their saved logical cursor")
local leftJunctionCursor = false
local rightJunctionCursor = false
for _, progress in ipairs(physicalActionProgress) do
    if progress.phase == "branch_return_to_junction" and progress.side == "left"
        and progress.nextAction == "descend_to_junction" then leftJunctionCursor = true end
    if progress.phase == "branch_return_to_junction" and progress.side == "right"
        and progress.nextAction == "descend_to_junction" then rightJunctionCursor = true end
end
assert(leftJunctionCursor and rightJunctionCursor,
    "each side should persist junction descent before its inverse movement")
assert(seenCursor["junction:none:restore_main_facing"],
    "junction-facing restoration should carry its saved logical cursor")
local seenStairAction = false
for _, progress in ipairs(physicalActionProgress) do
    if progress.workDomain == "shaft" and progress.floor == 4
        and progress.nextAction == "descend_stair_slice" then
        seenStairAction = true
    end
end
assert(seenStairAction, "stair movement should carry a durable floor-specific cursor")

local foundFinalPose = false
local foundFinalSummary = false
for _, line in ipairs(output) do
    if line:find("Final position: x=0, y=0, z=0", 1, true) then
        foundFinalPose = true
    end
    if line:find("Job summary:", 1, true) then foundFinalSummary = true end
end
assert(foundFinalPose, "active run should report its exact home pose")
assert(foundFinalSummary, "successful active run should report its final job summary")

print("active baseline wiring checks passed")
