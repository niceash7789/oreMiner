-- Branch Mining Program for ComputerCraft: Tweaked
-- Phase 1: Core Movement & Mining (MVP)

local Pose = require("src.navigation.pose")
local Motion = require("src.navigation.motion")
local Turn = require("src.navigation.turn")
local SlotGuard = require("src.inventory.slot_guard")
local ItemPolicy = require("src.config.item_policy")
local NumericValidation = require("src.config.numeric_validation")
local OreClassifier = require("src.mining.ore_classifier")
local itemConfig = require("src.config.defaults")
local Status = require("src.reporting.status")
local Reporting = require("src.reporting.safe")
local Statistics = require("src.reporting.statistics")
local KnownRoute = require("src.fuel.known_route")
local VeinTraversal = require("src.mining.vein_traversal")
local DigClear = require("src.safety.dig_clear")
local Result = require("src.safety.result")
local BranchProgress = require("src.mining.branch_progress")
local ReturnMove = require("src.navigation.return_move")
local MainTunnelScan = require("src.mining.main_tunnel_scan")
local MainShaftBackfill = require("src.mining.main_shaft_backfill")
local InventoryService = require("src.inventory.service")
local Checkpoint = require("src.persistence.checkpoint")
local MiningCursor = require("src.mining.cursor")

-- ============================================================================
-- GLOBAL STATE
-- ============================================================================

local pos, poseResult = Pose.new(0, 0, 0, 0)
if not pos then
    error(poseResult.code .. ": " .. poseResult.message)
end
local knownRoute, routeResult = KnownRoute.new(pos)
if not knownRoute then
    error(routeResult)
end
-- facing: 0=north(-z), 1=east(+x), 2=south(+z), 3=west(-x)

local config = {
    branch_length = 30,
    num_branches = 20,
    spacing = 3,
    fuel_reserve = 100,
    auto_refuel_coal = true,
    pave = itemConfig.paving.enabled,
    vein_mine = true,
    fuel = itemConfig.fuel,
    paving = itemConfig.paving,
    inventory = itemConfig.inventory,
    ore = itemConfig.ore,
    base = itemConfig.base,
}

local stats = Statistics.new({
    blocks_mined = 0,
    branches_completed = 0,
    fuel_used = 0,
    ores_mined = 0,
    veins_found = 0,
    service_trips = 0,
    branches_completed = 0,
    tunnel_blocks_mined = 0,
    torches_placed = 0,
    stair_slices_completed = 0,
    floors_completed = 0,
})
local terminalPrint = print
local function print(...)
    return Reporting.log(terminalPrint, ...)
end

local statePath = "oreMiner/state.json"
local checkpoint
local persistenceError
local fsApi = fs
local textutilsApi = textutils

local function configSnapshot()
    return {
        branch_length = config.branch_length,
        num_branches = config.num_branches,
        spacing = config.spacing,
        pave = config.pave,
        vein_mine = config.vein_mine,
    }
end

local function persist()
    if not checkpoint then return false end
    local ok, code = checkpoint:save(pos, knownRoute, configSnapshot())
    if not ok then persistenceError = code end
    return ok, code
end

local function persistMiningCursor(cursor)
    if not cursor then
        persistenceError = "INVALID_MINING_CURSOR"
        return false, persistenceError
    end
    if not checkpoint then return false, "STATE_NOT_INITIALIZED" end
    local ok, code = checkpoint:setProgress(cursor, pos, knownRoute, configSnapshot())
    if not ok then persistenceError = code end
    return ok, code
end

local function beginPhysicalAction(kind, direction)
    if not checkpoint then return false, "STATE_NOT_INITIALIZED" end
    local ok, code = checkpoint:beginAction(kind, direction, pos, knownRoute, configSnapshot())
    if not ok then persistenceError = code end
    return ok, code
end

local function markFatal(code)
    if checkpoint then
        local ok, saveCode = checkpoint:markFatal(code, pos, knownRoute, configSnapshot())
        if not ok then persistenceError = saveCode end
    end
end

local function newRun()
    local runId = tostring(os.epoch("utc"))
    checkpoint = Checkpoint.create(configSnapshot(), pos, knownRoute, runId,
        statePath, fsApi, textutilsApi)
    if not checkpoint then return false end
    local ok = persist()
    return ok
end

itemConfig.paving.enabled = config.pave

-- ============================================================================
-- FUEL MANAGEMENT
-- ============================================================================

local function fuelToReturn()
    local dist = math.abs(pos.x) + math.abs(pos.y) + math.abs(pos.z)
    local buffer = math.max(10, math.ceil(dist * 0.2))
    return dist + buffer
end

local function getFuelNeeded()
    local moves_per_position =
        config.spacing + (config.branch_length * 4)

    if config.vein_mine then
        moves_per_position = moves_per_position + 4
    end

    local total_moves =
        config.num_branches * moves_per_position

    local final_distance =
        config.num_branches * config.spacing

    local return_trip =
        final_distance + 50

    return total_moves + return_trip
end

local function refuel(needed)
    local level = turtle.getFuelLevel()

    if level == "unlimited" then
        return true
    end

    if level >= needed then
        return true
    end

    local guarded = SlotGuard.run(turtle, function()
        for slot = 1, 16 do
            local detail = turtle.getItemDetail(slot)
            if detail and ItemPolicy.isFuel(detail.name, config) then
                if turtle.select(slot) and turtle.refuel(0) then
                    while turtle.getFuelLevel() < needed
                        and turtle.getItemCount(slot) > 0 do
                        if not turtle.refuel(1) then
                            break
                        end
                    end

                    if turtle.getFuelLevel() >= needed then
                        return true
                    end
                end
            end
        end

        return turtle.getFuelLevel() >= needed
    end)

    return guarded.ok and guarded.value == true
end

local function tryAutoRefuelCoal()
    if not config.auto_refuel_coal then
        return
    end

    local level = turtle.getFuelLevel()

    if level == "unlimited" then
        return
    end

    if level >= config.fuel_reserve then
        return
    end

    local guarded = SlotGuard.run(turtle, function()
        local refueled = false

        for slot = 1, 16 do
            local detail = turtle.getItemDetail(slot)

            if detail and ItemPolicy.isFuel(detail.name, config) then
                if turtle.select(slot) then
                    while turtle.getFuelLevel() < config.fuel_reserve
                        and turtle.getItemCount(slot) > 0 do
                        if not turtle.refuel(1) then
                            break
                        end
                    end

                    refueled = true

                    if turtle.getFuelLevel() >= config.fuel_reserve then
                        break
                    end
                end
            end
        end

        return refueled
    end)

    if guarded.ok and guarded.value then
        print(
            string.format(
                "  [Fuel] Auto-refueled to %d",
                turtle.getFuelLevel()
            )
        )
    end
end

-- ============================================================================
-- POSITION TRACKING
-- ============================================================================

-- ============================================================================
-- CORE MOVEMENT FUNCTIONS
-- ============================================================================

local function move(movement)
    local updated, result = Motion.moveWithPolicy(pos, knownRoute, movement, turtle, {
        reserve = config.fuel_reserve,
        getFuelLevel = turtle.getFuelLevel,
        refuel = refuel,
        beforeMove = function() return beginPhysicalAction("move", movement) end,
    })
    if not result.ok then
        if result.code == "MOVE_FAILED" then
            local ok, code = checkpoint:cancelAction(pos, knownRoute, configSnapshot())
            if not ok then persistenceError = code end
        end
        if result.code ~= "MOVE_FAILED" then
            print(string.format("  [Fuel] Cannot safely move %s (%s)", movement, result.code))
        end
        return false, result.message or result.code
    end
    pos = updated
    stats:add("fuel_used", 1)
    local saved, saveCode = checkpoint:commitAction(pos, knownRoute, configSnapshot())
    if not saved then persistenceError = saveCode return false, persistenceError end
    return true
end

local function turn(direction)
    local ready, reason = beginPhysicalAction("turn", direction)
    if not ready then return false, reason end
    local updated, result = Motion.turn(pos, direction, turtle)
    if not result.ok then
        local ok, code = checkpoint:cancelAction(pos, knownRoute, configSnapshot())
        if not ok then persistenceError = code end
        return false, result
    end
    pos = updated
    local saved, saveCode = checkpoint:commitAction(pos, knownRoute, configSnapshot())
    if not saved then persistenceError = saveCode return false, { ok = false, code = persistenceError } end
    return true
end

local function forward() return move("forward") end
local function back() return move("back") end
local function up() return move("up") end
local function down() return move("down") end
local function turnLeft() return turn("left") end
local function turnRight() return turn("right") end

-- ============================================================================
-- SAFE DIGGING
-- ============================================================================

local function digForward()
    local result = DigClear.run({
        detect = turtle.detect,
        dig = turtle.dig,
        now = function() return os.epoch("utc") / 1000 end,
        maxAttempts = itemConfig.safety.digRetries,
        maxElapsed = itemConfig.safety.digTimeLimit,
        wait = function() sleep(0.5) end,
    })
    stats:add("blocks_mined", result.dug)
    if not result.ok then print("ERROR: " .. result.code .. " - " .. result.message) end
    return result
end

local function digUp()
    local result = DigClear.run({
        detect = turtle.detectUp,
        dig = turtle.digUp,
        now = function() return os.epoch("utc") / 1000 end,
        maxAttempts = itemConfig.safety.digRetries,
        maxElapsed = itemConfig.safety.digTimeLimit,
        wait = function() sleep(0.5) end,
    })
    stats:add("blocks_mined", result.dug)
    if not result.ok then print("ERROR: " .. result.code .. " - " .. result.message) end
    return result
end

local function digDown()
    local result = DigClear.run({
        detect = turtle.detectDown,
        dig = turtle.digDown,
        now = function() return os.epoch("utc") / 1000 end,
        maxAttempts = itemConfig.safety.digRetries,
        maxElapsed = itemConfig.safety.digTimeLimit,
        wait = function() sleep(0.5) end,
    })
    stats:add("blocks_mined", result.dug)
    if not result.ok then print("ERROR: " .. result.code .. " - " .. result.message) end
    return result
end

local function paveDown()
    if not config.pave then
        return false
    end

    if turtle.detectDown() then
        return false
    end

    local guarded = SlotGuard.run(turtle, function()
        local totals = {}
        for slot = 1, 16 do
            local detail = turtle.getItemDetail(slot)
            if detail then
                totals[detail.name] = (totals[detail.name] or 0) + turtle.getItemCount(slot)
            end
        end
        for slot = 1, 16 do
            local detail = turtle.getItemDetail(slot)

            local available = detail and totals[detail.name] or 0
            if detail and ItemPolicy.mayConsumeForPaving(
                detail.name, itemConfig, available
            ) then
                if turtle.select(slot) and turtle.placeDown() then
                    stats:add("blocks_placed", 1)
                    return true
                end
            end
        end

        return false
    end)

    return guarded.ok and guarded.value == true
end

-- ============================================================================
-- ORE VEIN MINING
-- ============================================================================

local function getPositionKey(x, y, z)
    return x .. "," .. y .. "," .. z
end

local function getForwardPosition()
    if pos.facing == 0 then
        return pos.x, pos.y, pos.z - 1
    elseif pos.facing == 1 then
        return pos.x + 1, pos.y, pos.z
    elseif pos.facing == 2 then
        return pos.x, pos.y, pos.z + 1
    else
        return pos.x - 1, pos.y, pos.z
    end
end

local function safeForward()
    local nextPose = Pose.afterMove(pos, "forward", true)
    local result = ReturnMove.run({
        hasEdge = function() return KnownRoute.hasEdge(knownRoute, pos, nextPose) end,
        move = function() return forward() end,
        maxAttempts = itemConfig.safety.digRetries,
        recover = function() sleep(0.5) end,
    })
    if not result.ok then print("ERROR: " .. result.code .. " - " .. result.message) end
    return result.ok
end

local function safeBack()
    if back() then
        return true, "RETURN_COMPLETE"
    end

    if turnRight() ~= true or turnRight() ~= true then
        return false, "RETURN_TURN_FAILED"
    end

    if safeForward() ~= true then
        return false, "RETURN_MOVE_FAILED"
    end

    if turnRight() ~= true or turnRight() ~= true then
        return false, "RETURN_TURN_FAILED"
    end

    return true, "RETURN_COMPLETE"
end

-- ============================================================================
-- INVENTORY SERVICE BOUNDARY
-- ============================================================================

local function turnToFacing(targetFacing)
    local faced, result = Turn.face(pos, targetFacing, function(direction)
        local succeeded, reason = turn(direction)
        if succeeded then return pos, { ok = true } end
        return pos, type(reason) == "table" and reason
            or { ok = false, code = "TURN_FAILED", message = tostring(reason), retryable = false }
    end)
    if faced then pos = faced end
    return result.ok, result
end

local inventoryService = InventoryService.new({
    turtle = turtle,
    config = config,
    itemConfig = itemConfig,
    pose = function() return pos end,
    turnToFacing = turnToFacing,
    safeForward = safeForward,
    up = up,
    down = down,
    report = function(message) print("  " .. message) end,
    reportError = function(message) print("ERROR: " .. message) end,
})
local inventoryPressureReached = inventoryService.pressureReached
local serviceInventoryRaw = inventoryService.serviceIfNeeded
local function serviceInventoryIfFull()
    local serviced, code = serviceInventoryRaw()
    if serviced and code == "SERVICE_COMPLETE" then stats:add("service_trips", 1) end
    return serviced
end
-- ============================================================================
-- VEIN MINING
-- ============================================================================

local veinInventoryPressureReached = false

local function copyCurrentPose()
    return { x = pos.x, y = pos.y, z = pos.z, facing = pos.facing }
end

local function mineVein(checkpoint, seedInverse)
    local movements = {
        forward = forward,
        back = back,
        up = up,
        down = down,
    }
    local function inspect(direction)
        local found, data
        if direction == "up" then
            found, data = turtle.inspectUp()
        elseif direction == "down" then
            found, data = turtle.inspectDown()
        else
            found, data = turtle.inspect()
        end
        return found, data
    end
    local result = VeinTraversal.run(checkpoint, {
        pose = function() return pos end,
        project = function(direction)
            local projected = { x = pos.x, y = pos.y, z = pos.z, facing = pos.facing }
            if direction == "up" then projected.y = projected.y + 1
            elseif direction == "down" then projected.y = projected.y - 1
            else
                local x, y, z = getForwardPosition()
                projected.x, projected.y, projected.z = x, y, z
            end
            return projected
        end,
        inspect = inspect,
        dig = function(direction)
            if direction == "up" then return digUp()
            elseif direction == "down" then return digDown()
            else return digForward() end
        end,
        move = function(direction)
            local moved = movements[direction]
            return moved and moved() or false
        end,
        turnRight = turnRight,
        inventoryPressure = inventoryPressureReached,
        reportCap = function(blocks, maxBlocks, maxRadius)
            print(string.format(
                "WARNING: Ore vein cap reached after %d blocks (limits: %d blocks / radius %d); continuing from checkpoint.",
                blocks,
                maxBlocks,
                maxRadius
            ))
        end,
    }, seedInverse, function(block)
        return OreClassifier.isOre(block, config.ore)
    end, function(block)
        Statistics.addOreCounts(stats, block, 1)
    end)
    stats:add("ores_mined", result.blocks - 1)
    veinInventoryPressureReached = result.code == "INVENTORY_RETURN"
    return result
end

local function sealMainShaftOpening(checkpoint, direction)
    local result = MainShaftBackfill.seal(checkpoint, direction, {
        pose = function() return pos end,
        selectCobblestone = function()
            for slot = 1, 16 do
                local detail = turtle.getItemDetail(slot)
                if detail and detail.name == "minecraft:cobblestone"
                    and turtle.getItemCount(slot) > 0 then
                    return turtle.select(slot) == true
                end
            end
            return false
        end,
        place = function(target)
            if target == "up" then return turtle.placeUp()
            elseif target == "down" then return turtle.placeDown()
            else return turtle.place() end
        end,
        inspect = function(target)
            if target == "up" then return turtle.inspectUp()
            elseif target == "down" then return turtle.inspectDown()
            else return turtle.inspect() end
        end,
    })
    if not result.ok then print("ERROR: " .. result.code) end
    return result
end

local function checkAndMineOre(mainShaftDirection)
    local hasBlock, data =
        turtle.inspect()

    if hasBlock
        and OreClassifier.isOre(data, config.ore) then

        stats:add("veins_found", 1)
        veinInventoryPressureReached = false

        local checkpoint = copyCurrentPose()
        local dug = digForward()
        if not dug.ok then
            return dug
        end
        stats:add("ores_mined", 1)
        if forward() ~= true then
            print("ERROR: VEIN_MOVE_FAILED")
            return Result.new(false, "VEIN_MOVE_FAILED", "Could not enter the exposed ore block")
        end
        local result = mineVein(checkpoint, "back")
        if not result.ok then return result end
        if mainShaftDirection then
            local sealed = sealMainShaftOpening(checkpoint, mainShaftDirection)
            if not sealed.ok then return sealed end
        end
        if veinInventoryPressureReached then
            local serviced = serviceInventoryIfFull()
            if serviced ~= true then return Result.new(false, "INVENTORY_SERVICE_FAILED") end
        end
    end
    return Result.new(true, "NO_ORE")
end

local function checkAndMineOreUp(mainShaftDirection)
    local hasBlock, data =
        turtle.inspectUp()

    if hasBlock
        and OreClassifier.isOre(data, config.ore) then

        stats:add("veins_found", 1)
        veinInventoryPressureReached = false

        local checkpoint = copyCurrentPose()
        local dug = digUp()
        if not dug.ok then
            return dug
        end
        stats:add("ores_mined", 1)
        if up() ~= true then
            print("ERROR: VEIN_MOVE_FAILED")
            return Result.new(false, "VEIN_MOVE_FAILED", "Could not enter the exposed ore block above")
        end
        local result = mineVein(checkpoint, "down")
        if not result.ok then return result end
        if mainShaftDirection then
            local sealed = sealMainShaftOpening(checkpoint, mainShaftDirection)
            if not sealed.ok then return sealed end
        end
        if veinInventoryPressureReached then
            local serviced = serviceInventoryIfFull()
            if serviced ~= true then return Result.new(false, "INVENTORY_SERVICE_FAILED") end
        end
    end
    return Result.new(true, "NO_ORE")
end

local function checkAndMineOreDown(mainShaftDirection)
    local hasBlock, data =
        turtle.inspectDown()

    if hasBlock
        and OreClassifier.isOre(data, config.ore) then

        stats:add("veins_found", 1)
        veinInventoryPressureReached = false

        local checkpoint = copyCurrentPose()
        local dug = digDown()
        if not dug.ok then
            return dug
        end
        stats:add("ores_mined", 1)
        if down() ~= true then
            print("ERROR: VEIN_MOVE_FAILED")
            return Result.new(false, "VEIN_MOVE_FAILED", "Could not enter the exposed ore block below")
        end
        local result = mineVein(checkpoint, "up")
        if not result.ok then return result end
        if mainShaftDirection then
            local sealed = sealMainShaftOpening(checkpoint, mainShaftDirection)
            if not sealed.ok then return sealed end
        end
        if veinInventoryPressureReached then
            local serviced = serviceInventoryIfFull()
            if serviced ~= true then return Result.new(false, "INVENTORY_SERVICE_FAILED") end
        end
    end
    return Result.new(true, "NO_ORE")
end

-- ============================================================================
-- MINING FUNCTIONS
-- ============================================================================

local function mineForward()
    local forwardDig = digForward()
    if not forwardDig.ok then return forwardDig end
    local overheadDig = digUp()
    if not overheadDig.ok then return overheadDig end

    local attempts = 0

    while not forward() do
        attempts =
            attempts + 1

        if attempts > 10 then
            print(
                "ERROR: Cannot move forward after 10 attempts"
            )

            return Result.new(false, "MOVE_FAILED", "Cannot move forward after bounded retries")
        end

        if turtle.detect() then

            if not turtle.dig() then
                print(
                    "ERROR: Cannot dig block (bedrock?)"
                )

                return Result.new(false, "UNBREAKABLE_BLOCK", "Cannot dig the detected forward block")
            end

        elseif turtle.attack() then

        else
            sleep(0.5)
        end
    end

    stats:add("tunnel_blocks_mined", 1)
    paveDown()

    return Result.new(true, "MINED_FORWARD")
end

local function scanMainCell()
    if not config.vein_mine then
        return true
    end

    local result = MainTunnelScan.scanCell({
        facing = function() return pos.facing end,
        scan = function(direction)
            if direction == "left" then
                if turnLeft() ~= true then return Result.new(false, "TURN_FAILED") end
                local scanned = checkAndMineOre("forward")
                if scanned ~= true then return scanned end
                if turnRight() ~= true then return Result.new(false, "TURN_FAILED") end
                return Result.new(true, "SCAN_COMPLETE")
            elseif direction == "right" then
                if turnRight() ~= true or turnRight() ~= true then return Result.new(false, "TURN_FAILED") end
                local scanned = checkAndMineOre("forward")
                if scanned ~= true then return scanned end
                if turnLeft() ~= true or turnLeft() ~= true then return Result.new(false, "TURN_FAILED") end
                return Result.new(true, "SCAN_COMPLETE")
            elseif direction == "down" then
                return checkAndMineOreDown(direction)
            elseif direction == "up" then
                return checkAndMineOreUp(direction)
            end
            return Result.new(false, "INVALID_SCAN_DIRECTION")
        end,
    })
    if not result.ok then print("ERROR: " .. result.code) end
    return result.ok
end

local function mineBranch(length, branchPair, side, mainOffset)
    local outboundResult = BranchProgress.run(length, function(i)
        local cursor = MiningCursor.branch(branchPair, side, "branch_outbound_lower",
            i - 1, mainOffset, "mine_branch_cell")
        if not persistMiningCursor(cursor) then
            return { ok = false, code = persistenceError or "STATE_WRITE_FAILED",
                message = "Unable to save branch outbound cursor" }
        end
        if not serviceInventoryIfFull() then
            return { ok = false, code = "INVENTORY_SERVICE_FAILED", message = "Inventory service failed during branch mining" }
        end

        local mined = mineForward()
        if not mined.ok then
            return mined
        end

        if config.vein_mine then

            turnLeft()
            local scanned = checkAndMineOre()
            if not scanned.ok then return scanned end
            turnRight()

            turnRight()
            local scanned = checkAndMineOre()
            if not scanned.ok then return scanned end
            turnLeft()

            local scanned = checkAndMineOreDown()
            if not scanned.ok then return scanned end
        end

        if not serviceInventoryIfFull() then
            return { ok = false, code = "INVENTORY_SERVICE_FAILED", message = "Inventory service failed during branch mining" }
        end
        return true
    end)

    if not outboundResult.ok then
        print("ERROR: " .. outboundResult.code .. " (completed "
            .. outboundResult.completed .. "/" .. outboundResult.requested .. ")")
        return false, outboundResult
    end

    local turnaroundCursor = MiningCursor.branch(branchPair, side, "branch_turnaround",
        length, mainOffset, "prepare_branch_return")
    if not persistMiningCursor(turnaroundCursor) then return false end

    local clearedAbove = digUp()
    if not clearedAbove.ok then
        return false, clearedAbove
    end

    if config.vein_mine then

        if up() ~= true then
            print("ERROR: BRANCH_RETURN_MOVE_FAILED")
            return false
        end

        turnRight()
        turnRight()

        for i = 1, length do

            local returnCursor = MiningCursor.branch(branchPair, side, "branch_upper_return",
                length - i + 1, mainOffset, "scan_and_return_branch_cell")
            if not persistMiningCursor(returnCursor) then return false end

            if not serviceInventoryIfFull() then
                return false
            end

            turnLeft()
            checkAndMineOre()
            turnRight()

            turnRight()
            checkAndMineOre()
            turnLeft()

            checkAndMineOreUp()

            if not serviceInventoryIfFull() then
                return false
            end

            if safeForward() ~= true then
                print("ERROR: BRANCH_RETURN_MOVE_FAILED")
                return false
            end
        end

        local junctionCursor = MiningCursor.branch(branchPair, side,
            "branch_return_to_junction", 0, mainOffset, "descend_to_junction")
        if not persistMiningCursor(junctionCursor) then return false end

        if down() ~= true then
            print("ERROR: BRANCH_RETURN_MOVE_FAILED")
            return false
        end

    else

        turnRight()
        turnRight()

        for i = 1, length do

            local returnCursor = MiningCursor.branch(branchPair, side, "branch_lower_return",
                length - i + 1, mainOffset, "return_branch_cell")
            if not persistMiningCursor(returnCursor) then return false end

            if not safeForward() then
                print("ERROR: BRANCH_RETURN_MOVE_FAILED")
                return false
            end
        end
    end

    return true
end

-- ============================================================================
-- FUEL STATUS
-- ============================================================================

local function printFuelStatus(branch_num)
    local level =
        turtle.getFuelLevel()

    if level == "unlimited" then
        return
    end

    local returnCost =
        fuelToReturn()

    local remaining_branches =
        config.num_branches
        - branch_num

    local moves_per_branch =
        config.spacing
        + (config.branch_length * 4)

    if config.vein_mine then
        moves_per_branch =
            moves_per_branch + 4
    end

    local fuel_to_finish =
        remaining_branches
        * moves_per_branch

    local efficiency = "N/A"

    if stats:get("fuel_used") > 0 then
        efficiency =
            string.format(
                "%.1f",
                stats:get("blocks_mined")
                    / stats:get("fuel_used")
            )
    end

    print(
        string.format(
            "  [Fuel] Level: %d | Return cost: %d | To finish: ~%d | Blocks/fuel: %s",
            level,
            returnCost,
            fuel_to_finish,
            efficiency
        )
    )
end

-- ============================================================================
-- MAIN MINING PATTERN
-- ============================================================================

local function executeMining()

    local startedAt = os.epoch("utc") / 1000

    local fuelLevel =
        turtle.getFuelLevel()

    local fuelNeeded =
        getFuelNeeded()

    print("=== Fuel Check ===")

    if fuelLevel == "unlimited" then

        print(
            "Fuel: unlimited (creative mode)"
        )

    else

        print(
            string.format(
                "Current fuel: %d",
                fuelLevel
            )
        )

        print(
            string.format(
                "Estimated needed: %d",
                fuelNeeded
            )
        )

        if fuelLevel < fuelNeeded then

            print("")
            print(
                "WARNING: Low fuel! Attempting to refuel..."
            )

            if not refuel(fuelNeeded) then

                print(
                    "Could not get enough fuel."
                )

                print(
                    "Continuing anyway, will try to refuel during operation."
                )

            else

                print(
                    string.format(
                        "Refueled! New level: %d",
                        turtle.getFuelLevel()
                    )
                )
            end
        end
    end

    print("")

    print(
        "Starting branch mining operation..."
    )

    print(
        string.format(
            "Position: x=%d, y=%d, z=%d, facing=%d",
            pos.x,
            pos.y,
            pos.z,
            pos.facing
        )
    )

    print("")

    for branch = 1, config.num_branches do

        print(Status.phase("MAIN", branch, config.num_branches, "main"))

        for step = 1, config.spacing do

            local mainCursor = MiningCursor.mainShaft(branch, step, branch - 1)
            if not persistMiningCursor(mainCursor) then return false end

            if not serviceInventoryIfFull() then
                return false
            end

            if not mineForward() then

                print(
                    "ERROR: Mining stopped in main tunnel"
                )

                return false
            end

            if not scanMainCell() then
                return false
            end

            -- Preserve the baseline's canonical junction pose without
            -- advancing the branch grid: each spacing cell is scanned from
            -- the cell just entered, then the checked edge is retraced.
            if step < config.spacing and not safeBack() then
                print("ERROR: MAIN_SCAN_RETURN_MOVE_FAILED")
                return false
            end

            if not serviceInventoryIfFull() then
                return false
            end
        end

        print(Status.phase("BRANCH", branch, config.num_branches, "L out"))

        local leftJunctionCursor = MiningCursor.junction(branch, branch, "turn_to_left_branch")
        if not persistMiningCursor(leftJunctionCursor) then return false end

        turnLeft()

        if not mineBranch(
            config.branch_length,
            branch,
            "left",
            branch
        ) then

            print(
                "ERROR: Left branch mining failed"
            )

            return false
        end

        tryAutoRefuelCoal()

        if not serviceInventoryIfFull() then
            return false
        end

        print(Status.phase("BRANCH", branch, config.num_branches, "R out"))

        if not mineBranch(
            config.branch_length,
            branch,
            "right",
            branch
        ) then

            print(
                "ERROR: Right branch mining failed"
            )

            return false
        end

        tryAutoRefuelCoal()

        if not serviceInventoryIfFull() then
            return false
        end

        local mainFacingCursor = MiningCursor.junction(branch, branch, "restore_main_facing")
        if not persistMiningCursor(mainFacingCursor) then return false end

        turnRight()

        stats:add("branches_completed", 1)

        local currentFuel =
            turtle.getFuelLevel()

        local fuelStr =
            currentFuel == "unlimited"
            and "unlimited"
            or tostring(currentFuel)

        print(Status.branchComplete(branch, config.num_branches, stats:get("blocks_mined"), fuelStr))

        printFuelStatus(branch)

        print("")
    end

    print("")
    print(
        "=== Mining Complete! ==="
    )

    local summary = Statistics.jobSummary(stats, {
        startedAt = startedAt,
        endedAt = os.epoch("utc") / 1000,
    })
    for _, line in ipairs(Statistics.formatJobSummary(summary)) do print(line) end
    for key, amount in pairs(summary.oreByType) do
        if key:sub(1, 9) == "ore_type:" and amount > 0 then
            print(string.format("Ore %s: %d", key:sub(10), amount))
        end
    end

    print(
        string.format(
            "Total branches: %d",
            stats:get("branches_completed")
        )
    )

    print(
        string.format(
            "Total blocks mined: %d",
            stats:get("blocks_mined")
        )
    )

    print(
        string.format(
            "Fuel used: %d",
            stats:get("fuel_used")
        )
    )

    local endFuel =
        turtle.getFuelLevel()

    if endFuel ~= "unlimited" then

        print(
            string.format(
                "Ending fuel: %d",
                endFuel
            )
        )

        if stats:get("fuel_used") > 0 then

            print(
                string.format(
                    "Mining efficiency: %.1f blocks/fuel",
                    stats:get("blocks_mined")
                        / stats:get("fuel_used")
                )
            )
        end
    end

    if config.vein_mine then

        print(
            string.format(
                "Veins found: %d",
                stats:get("veins_found")
            )
        )

        print(
            string.format(
                "Ore blocks mined: %d",
                stats:get("ores_mined")
            )
        )
    end

    print(
        string.format(
            "Final position: x=%d, y=%d, z=%d",
            pos.x,
            pos.y,
            pos.z
        )
    )

    return true
end

-- ============================================================================
-- USER INTERFACE
-- ============================================================================

local function getUserInput(
    prompt,
    default
)

    write(
        prompt
            .. " (default: "
            .. tostring(default)
            .. "): "
    )

    local input = read()

    if input == ""
        or input == nil then

        return default
    end

    local value = tonumber(input)
    while value == nil or value ~= math.floor(value) do
        print("Enter a whole number.")
        write(prompt .. " (default: " .. tostring(default) .. "): ")
        input = read()
        if input == "" or input == nil then return default end
        value = tonumber(input)
    end
    return value
end

local function getConfiguration()

    print(
        "=== Branch Mining Configuration ==="
    )

    print("")

    config.branch_length =
        getUserInput(
            "Branch length",
            30
        )

    config.num_branches =
        getUserInput(
            "Number of branches",
            20
        )

    config.spacing =
        getUserInput(
            "Spacing between branches",
            3
        )

    local validConfig, configError = NumericValidation.validate(config)
    while not validConfig do
        print("Invalid configuration: " .. configError)
        config.branch_length = getUserInput("Branch length", 30)
        config.num_branches = getUserInput("Number of branches", 20)
        config.spacing = getUserInput("Spacing between branches", 3)
        validConfig, configError = NumericValidation.validate(config)
    end

    write("Enable floor paving? (y/n, default: n): ")

    local paveInput = read()

    config.pave = paveInput == "y" or paveInput == "Y"

    write(
        "Enable ore vein mining? (y/n, default: y): "
    )

    local veinInput = read()

    config.vein_mine =
        veinInput ~= "n"
        and veinInput ~= "N"

    print("")
    print("Configuration:")

    print(
        "  Branch length: "
            .. config.branch_length
    )

    print(
        "  Number of branches: "
            .. config.num_branches
    )

    print(
        "  Spacing: "
            .. config.spacing
    )

    print(
        "  Floor paving: "
            .. (
                config.pave
                and "yes"
                or "no"
            )
    )

    print(
        "  Ore vein mining: "
            .. (
                config.vein_mine
                and "yes"
                or "no"
            )
    )

    print(
        "  Chest unload: enabled"
    )

    print(
        "  Chest position: directly behind start"
    )

    print(
        "  Keeps: configured item quantities, all torches and protected items"
    )

    print("")

    write(
        "Start mining? (y/n): "
    )

    local confirm = read()

    return confirm == "y"
        or confirm == "Y"
        or confirm == ""
end

-- ============================================================================
-- MAIN
-- ============================================================================

local function main()

    print(
        "=== ComputerCraft Branch Mining Program ==="
    )

    print("")

    if type(fsApi) ~= "table" or type(textutilsApi) ~= "table"
        or type(fsApi.combine) ~= "function" then
        error("PERSISTENCE_API_UNAVAILABLE")
    end
    statePath = fsApi.combine("oreMiner", "state.json")
    if not fsApi.exists("oreMiner") then fsApi.makeDir("oreMiner") end
    local existing, stateCode = Checkpoint.load(statePath, configSnapshot(), fsApi, textutilsApi)
    if stateCode == "POSITION_UNCERTAIN" then
        error("POSITION_UNCERTAIN: pending movement or turn; reconcile pose before any action")
    elseif stateCode == "STATE_CORRUPT" then
        error("STATE_CORRUPT: active state and backup are invalid; refusing to overwrite")
    elseif stateCode == "CONFIG_MISMATCH" then
        error("CONFIG_MISMATCH: saved run configuration differs from current configuration")
    elseif existing and existing:status() ~= "complete" then
        error("ACTIVE_STATE_PRESENT: resume support is not implemented; refusing to restart mining")
    elseif getConfiguration() then
        if not newRun() then error("STATE_WRITE_FAILED: unable to create initial snapshot") end
        local ok = executeMining()
        if ok then
            local saved, saveCode = checkpoint:markComplete(pos, knownRoute, configSnapshot())
            if not saved then persistenceError = saveCode end
        else
            markFatal(persistenceError or "MINING_STOPPED")
        end
    else
        print("Mining cancelled.")
    end
end

main()

