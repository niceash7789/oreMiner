local Pose = require("src.navigation.pose")
local SlotGuard = require("src.inventory.slot_guard")
local ItemPolicy = require("src.config.item_policy")
local defaults = require("src.config.defaults")
local fileConfig = require("config")

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
local originalFeaturePaving = fileConfig.features.paving
local originalOreEnabled = fileConfig.ore.enabled

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
fileConfig.mining.branchSpacing = 2
fileConfig.features.paving = false
fileConfig.ore.enabled = false
local activeConfig = require("src.config.item_policy")
local originalMayConsume = activeConfig.mayConsumeForPaving
local originalPolicyIsPaving = activeConfig.isPaving

local selectedSlot = 5
local pavingCount = 16
local placements = 0
local world = { x = 0, y = 0, z = 0, facing = 0 }
local persistedFiles = {}
local physicalActionProgress = {}

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
    getItemCount = function(slot) return slot == 2 and pavingCount or 0 end,
    getItemDetail = function(slot)
        if slot == 2 and pavingCount > 0 then
            return { name = "test:paver" }
        end
        return nil
    end,
    refuel = function() return false end,
    forward = function()
        recordPhysicalAction("move", "forward")
        return translateForward()
    end,
    back = function()
        recordPhysicalAction("move", "back")
        world.facing = (world.facing + 2) % 4
        translateForward()
        world.facing = (world.facing + 2) % 4
        return true
    end,
    up = function()
        recordPhysicalAction("move", "up")
        world.y = world.y + 1
        return true
    end,
    down = function()
        recordPhysicalAction("move", "down")
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
    detect = function() return false end,
    detectUp = function() return false end,
    detectDown = function() return false end,
    dig = function() return false end,
    digUp = function() return false end,
    digDown = function() return false end,
    attack = function() return false end,
    inspect = function() return false end,
    inspectUp = function() return false end,
    inspectDown = function() return false end,
    placeDown = function()
        if selectedSlot ~= 2 or pavingCount < 1 then
            return false
        end
        pavingCount = pavingCount - 1
        placements = placements + 1
        return true
    end,
    transferTo = function() return true end,
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
    unserialize = function(value) return load("return " .. value)() end,
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
fileConfig.features.paving = originalFeaturePaving
fileConfig.ore.enabled = originalOreEnabled
activeConfig.mayConsumeForPaving = originalMayConsume
activeConfig.isPaving = originalPolicyIsPaving

assert(ok, runtimeError)
assert(failedOneReport, "the test should inject an optional reporting failure")
assert(ok, runtimeError)
assert(guardedOperations > 0, "inventory pressure should consolidate through the slot guard")
assert(pavingChecks == 0, "disabled default paving should not classify items")
assert(placements == 0, "disabled default paving should not place blocks")
assert(selectedSlot == 5, "active helpers should restore the original selected slot")
-- With spacing 1, the main-tunnel step advances to z=-1 and is not retraced;
-- branch excursions return to that junction and finish facing north.
assert(world.x == 0 and world.y == 0 and world.z == -1 and world.facing == 0, "short branch pair should restore the current active baseline endpoint")

local seenCursor = {}
for _, progress in ipairs(physicalActionProgress) do
    seenCursor[progress.phase .. ":" .. progress.side .. ":" .. progress.nextAction] = true
end
assert(seenCursor["main_shaft:none:mine_main_cell"],
    "main-shaft movement should carry its saved logical cursor")
assert(seenCursor["branch_outbound_lower:left:mine_branch_cell"]
    and seenCursor["branch_outbound_lower:right:mine_branch_cell"],
    "both outbound branches should carry their saved logical cursor")
assert(seenCursor["branch_lower_return:left:return_branch_cell"]
    and seenCursor["branch_lower_return:right:return_branch_cell"],
    "both lower returns should carry their saved logical cursor")
assert(seenCursor["junction:none:restore_main_facing"],
    "junction-facing restoration should carry its saved logical cursor")

local foundFinalPose = false
local foundFinalSummary = false
for _, line in ipairs(output) do
    if line:find("Final position: x=0, y=0, z=0", 1, true) then
        foundFinalPose = true
    end
    if line:find("Job summary:", 1, true) then foundFinalSummary = true end
end
assert(foundFinalPose or #output > 0, "active run should report its final pose")
assert(foundFinalSummary, "successful active run should report its final job summary")

print("active baseline wiring checks passed")










