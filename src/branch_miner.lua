-- Branch Mining Program for ComputerCraft: Tweaked
-- Phase 1: Core Movement & Mining (MVP)

local Pose = require("src.navigation.pose")
local Motion = require("src.navigation.motion")
local Turn = require("src.navigation.turn")
local SlotGuard = require("src.inventory.slot_guard")
local Paving = require("src.inventory.paving")
local PressureGate = require("src.inventory.pressure_gate")
local Refuel = require("src.fuel.refuel")
local FuelLevel = require("src.fuel.level")
local ItemPolicy = require("src.config.item_policy")
local ConfigLoader = require("src.config.loader")
local OreClassifier = require("src.mining.ore_classifier")
local configLoaded, rawConfig = pcall(require, "config")
if not configLoaded then
    error("CONFIG_INVALID: unable to load config.lua: " .. tostring(rawConfig))
end
local config, configResult = ConfigLoader.normalize(rawConfig)
if not config then
    error(configResult.code .. ": " .. (configResult.message or "configuration rejected"))
end
local itemConfig = config
local Status = require("src.reporting.status")
local Reporting = require("src.reporting.safe")
local Statistics = require("src.reporting.statistics")
local KnownRoute = require("src.fuel.known_route")
local RouteFuelPolicy = require("src.fuel.route_policy")
local VeinTraversal = require("src.mining.vein_traversal")
local DigClear = require("src.safety.dig_clear")
local ForwardRecovery = require("src.safety.forward_recovery")
local Pressure = require("src.inventory.pressure")
local Result = require("src.safety.result")
local BranchProgress = require("src.mining.branch_progress")
local BranchTraversal = require("src.navigation.branch_traversal")
local FloorGrid = require("src.navigation.floor_grid")
local ReturnMove = require("src.navigation.return_move")
local RouteHome = require("src.navigation.route_home")
local ResumeCommitment = require("src.fuel.resume_commitment")
local StairRoute = require("src.navigation.stair_route")
local FloorLanding = require("src.navigation.floor_landing")
local MainTunnelScan = require("src.mining.main_tunnel_scan")
local OreCandidateQueue = require("src.mining.ore_candidate_queue")
local MainShaftBackfill = require("src.mining.main_shaft_backfill")
local Lighting = require("src.lighting.right_wall")
local InventoryService = require("src.inventory.service")
local Resupply = require("src.inventory.resupply")
local Chest = require("src.inventory.chest")
local BranchEjection = require("src.inventory.branch_ejection")
local Checkpoint = require("src.persistence.checkpoint")
local PhysicalAction = require("src.persistence.physical_action")
local Recovery = require("src.persistence.recovery")
local MiningCursor = require("src.mining.cursor")
local RecoveryStatus = require("src.reporting.recovery_status")
local Startup = require("src.persistence.startup")

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
    active_runtime_seconds = 0,
})
local terminalPrint = print
local function print(...)
    return Reporting.log(terminalPrint, ...)
end

local statePath = "oreMiner/state.json"
local checkpoint
local persistenceError
local activeFloor = 0
local statisticsStartedAt = os.epoch("utc") / 1000
local fsApi = fs
local textutilsApi = textutils

local function configSnapshot()
    return {
        branch_length = config.branch_length,
        num_branches = config.num_branches,
        spacing = config.spacing,
        pave = config.pave,
        vein_mine = config.vein_mine,
        floor_count = config.mining.floorCount,
        stair_steps_per_floor = config.mining.stairStepsPerFloor,
        first_floor_depth_offset = config.mining.firstFloorDepthOffset,
        surface_entry_length = config.mining.surfaceEntryLength,
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
    if type(minerExitRequested) == "function" and minerExitRequested() then
        error("EXIT_REQUESTED", 0)
    end
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
    statisticsStartedAt = os.epoch("utc") / 1000
    checkpoint:setStatisticsProvider(function()
        local snapshot = stats:snapshot()
        snapshot.active_runtime_seconds = stats:get("active_runtime_seconds")
            + math.max(0, os.epoch("utc") / 1000 - statisticsStartedAt)
        return snapshot
    end)
    local initialCursor = MiningCursor.stairs(1, 0, "enter_surface")
    local ok = initialCursor and checkpoint:setProgress(
        initialCursor, pos, knownRoute, configSnapshot())
    return ok
end

local refuel

-- A route may start only when the turtle can afford its first move and retain
-- the configured emergency reserve. Per-move route admission handles growth
-- in the known return path after the route has begun.
local function hasStartupFuel()
    local level = turtle.getFuelLevel()
    if FuelLevel.isUnlimited(level) then return true end
    if type(level) ~= "number" then
        persistenceError = "INVALID_FUEL_LEVEL"
        return false
    end
    if level >= config.fuel_reserve then return true end
    if refuel(config.fuel_reserve) then return true end
    persistenceError = "NO_FUEL"
    return false
end

-- ============================================================================
-- FUEL MANAGEMENT
-- ============================================================================

local function fuelToReturn()
    local dist = math.abs(pos.x) + math.abs(pos.y) + math.abs(pos.z)
    local buffer = math.max(10, math.ceil(dist * 0.2))
    return dist + buffer
end

refuel = function(needed)
    local ready = Refuel.toTarget(turtle, needed, config)
    return ready == true
end

local function tryAutoRefuelCoal()
    if not config.auto_refuel_coal then
        return
    end

    local level = turtle.getFuelLevel()

    if FuelLevel.isUnlimited(level) then
        return
    end

    if type(level) == "number" and level >= config.fuel_reserve then
        return
    end

    local refueled = Refuel.toTarget(turtle, config.fuel_reserve, config)

    if refueled then
        print(
            string.format(
                "  [Fuel] Auto-refueled to %s",
                FuelLevel.format(turtle.getFuelLevel())
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

local lastMovementOutcome
local deferVeinMovementCommit = false
local veinMovementCommitPending = false
local stairRouteAction
local move
local turn

local function attemptMove(movement)
    if type(minerExitRequested) == "function" and minerExitRequested() then
        error("EXIT_REQUESTED", 0)
    end
    local updated, result = Motion.moveWithPolicy(pos, knownRoute, movement, turtle, {
        reserve = config.fuel_reserve,
        getFuelLevel = turtle.getFuelLevel,
        refuel = refuel,
        beforeMove = function()
            if veinMovementCommitPending then
                local saved, code = checkpoint:beginAction("move", movement,
                    pos, knownRoute, configSnapshot())
                if not saved then persistenceError = code end
                return saved, code
            end
            if stairRouteAction then
                local action = movement == "forward" and "forward" or movement
                local saved, code = checkpoint:beginRouteAction(action, "move", movement,
                    pos, knownRoute, configSnapshot())
                if not saved then persistenceError = code end
                return saved, code
            end
            return beginPhysicalAction("move", movement)
        end,
    })
    lastMovementOutcome = result
    if not result.ok then
        if result.code == "MOVE_FAILED" then
            local ok, code
            if stairRouteAction then
                local action = movement == "forward" and "forward" or movement
                ok, code = checkpoint:cancelRouteAction(action, pos, knownRoute, configSnapshot())
            else
                ok, code = checkpoint:cancelAction(pos, knownRoute, configSnapshot())
            end
            if not ok then
                persistenceError = code
                lastMovementOutcome = { ok = false, code = code }
                return false, Result.new(false, code or "PERSISTENCE_FAILED")
            end
        end
        if result.code ~= "MOVE_FAILED" then
            print(string.format("  [Fuel] Cannot safely move %s (%s)", movement, result.code))
        end
        return false, Result.new(false, result.code, result.message,
            { retryable = result.retryable == true })
    end
    pos = updated
    stats:add("fuel_used", result.fuelUsed or 0)
    if deferVeinMovementCommit then
        veinMovementCommitPending = true
    elseif stairRouteAction then
        local inverse = movement == "forward" and "back"
            or movement == "back" and "forward"
            or movement == "up" and "down"
            or movement == "down" and "up"
        local saved, saveCode = checkpoint:commitRouteAction(inverse, pos, knownRoute, configSnapshot())
        if not saved then
            persistenceError = saveCode
            lastMovementOutcome = { ok = false, code = persistenceError }
            return false, persistenceError
        end
    elseif veinMovementCommitPending then
        -- Vein traversal commits the matching DFS edge immediately afterward.
    else
        local saved, saveCode = checkpoint:commitAction(pos, knownRoute, configSnapshot())
        if not saved then
            persistenceError = saveCode
            lastMovementOutcome = { ok = false, code = persistenceError }
            return false, persistenceError
        end
    end
    return true, Result.new(true, "MOVE_COMMITTED", nil, { retryable = false })
end

turn = function(direction)
    if type(minerExitRequested) == "function" and minerExitRequested() then
        error("EXIT_REQUESTED", 0)
    end
    local expectedAction = direction == "left" and "turnLeft" or "turnRight"
    local ready, reason
    if veinMovementCommitPending then
        ready, reason = checkpoint:beginAction("turn", direction,
            pos, knownRoute, configSnapshot())
        if not ready then persistenceError = reason end
    elseif stairRouteAction then
        ready, reason = checkpoint:beginRouteAction(expectedAction, "turn", direction,
            pos, knownRoute, configSnapshot())
        if not ready then persistenceError = reason end
    else
        ready, reason = beginPhysicalAction("turn", direction)
    end
    if not ready then
        local code = type(reason) == "table" and reason.code or tostring(reason or "ACTION_INTENT_FAILED")
        return false, Result.new(false, code, type(reason) == "table" and reason.message or nil,
            { retryable = false })
    end
    local updated, result = Motion.turn(pos, direction, turtle)
    if not result.ok then
        local ok, code
        if stairRouteAction then
            ok, code = checkpoint:cancelRouteAction(expectedAction, pos, knownRoute, configSnapshot())
        else
            ok, code = checkpoint:cancelAction(pos, knownRoute, configSnapshot())
        end
        if not ok then persistenceError = code end
        return false, Result.new(false, result.code, result.message,
            { retryable = result.retryable == true })
    end
    pos = updated
    local inverse = direction == "left" and "turnRight" or "turnLeft"
    local saved, saveCode
    if stairRouteAction then
        saved, saveCode = checkpoint:commitRouteAction(inverse, pos, knownRoute, configSnapshot())
    elseif veinMovementCommitPending then
        veinMovementCommitPending = false
        saved, saveCode = checkpoint:commitAction(pos, knownRoute, configSnapshot())
    else
        saved, saveCode = checkpoint:commitAction(pos, knownRoute, configSnapshot())
    end
    if not saved then
        persistenceError = saveCode
        return false, Result.new(false, persistenceError, nil, { retryable = false })
    end
    return true, Result.new(true, "TURN_COMMITTED", nil, { retryable = false })
end

local function forward()
    local moved, outcome = move("forward")
    if moved then return true, outcome end
    return false, outcome
end
local function forwardIntoVein()
    deferVeinMovementCommit = true
    local moved, outcome = move("forward")
    deferVeinMovementCommit = false
    if moved then return true, outcome end
    return false, outcome
end
local function back() return move("back") end
local function up() return move("up") end
local function down() return move("down") end
local function turnLeft() return turn("left") end
local function turnRight() return turn("right") end

-- ============================================================================
-- SAFE DIGGING
-- ============================================================================

local function digForward(optional)
    local digFailure
    local result = DigClear.run({
        detect = turtle.detect,
        inspect = function() local found, data = turtle.inspect(); return found and data or nil end,
        dig = function()
            local outcome = PhysicalAction.run(checkpoint, "dig", "forward", pos,
                knownRoute, configSnapshot(), turtle.dig)
            if outcome.ok ~= true then digFailure = outcome end
            return outcome.ok == true
        end,
        onBlock = function(name) print("Digging forward: " .. name) end,
        now = function() return os.epoch("utc") / 1000 end,
        maxAttempts = itemConfig.safety.digRetries,
        maxElapsed = itemConfig.safety.digTimeLimit,
        wait = function() sleep(0.5) end,
    })
    local dugCount = result.dug or 0
    if digFailure then result = digFailure end
    if dugCount > 0 then stats:add("blocks_mined", dugCount) end
    if not result.ok and not optional then
        print("ERROR: " .. result.code .. " - " .. tostring(result.message))
    end
    return result
end

local function digUp()
    local digFailure
    local result = DigClear.run({
        detect = turtle.detectUp,
        inspect = function() local found, data = turtle.inspectUp(); return found and data or nil end,
        dig = function()
            local outcome = PhysicalAction.run(checkpoint, "dig", "up", pos,
                knownRoute, configSnapshot(), turtle.digUp)
            if outcome.ok ~= true then digFailure = outcome end
            return outcome.ok == true
        end,
        onBlock = function(name) print("Digging above: " .. name) end,
        now = function() return os.epoch("utc") / 1000 end,
        maxAttempts = itemConfig.safety.digRetries,
        maxElapsed = itemConfig.safety.digTimeLimit,
        wait = function() sleep(0.5) end,
    })
    if digFailure then result = digFailure end
    stats:add("blocks_mined", result.dug or 0)
    if not result.ok then print("ERROR: " .. result.code .. " - " .. tostring(result.message)) end
    return result
end

local function digDown()
    local digFailure
    local result = DigClear.run({
        detect = turtle.detectDown,
        inspect = function() local found, data = turtle.inspectDown(); return found and data or nil end,
        dig = function()
            local outcome = PhysicalAction.run(checkpoint, "dig", "down", pos,
                knownRoute, configSnapshot(), turtle.digDown)
            if outcome.ok ~= true then digFailure = outcome end
            return outcome.ok == true
        end,
        onBlock = function(name) print("Digging below: " .. name) end,
        now = function() return os.epoch("utc") / 1000 end,
        maxAttempts = itemConfig.safety.digRetries,
        maxElapsed = itemConfig.safety.digTimeLimit,
        wait = function() sleep(0.5) end,
    })
    if digFailure then result = digFailure end
    stats:add("blocks_mined", result.dug or 0)
    if not result.ok then print("ERROR: " .. result.code .. " - " .. tostring(result.message)) end
    return result
end

local function atRear(callback)
    local originalFacing = pos.facing
    local function restoreFacing()
        for _ = 1, 3 do
            if pos.facing == originalFacing then return true end
            local turned, outcome = turn("right")
            if not turned then return false, outcome end
        end
        return false, Result.new(false, "POSITION_ERROR", "Rear clearing did not restore facing")
    end
    for _ = 1, 2 do
        local turned, outcome = turn("right")
        if not turned then
            local restored, restoreOutcome = restoreFacing()
            return nil, restored and outcome or restoreOutcome
        end
    end
    local ran, value = pcall(callback)
    local restored, restoreOutcome = restoreFacing()
    if not restored then return nil, restoreOutcome end
    if not ran then
        return nil, Result.new(false, "REAR_ACTION_FAILED", tostring(value))
    end
    if value == nil then
        return nil, Result.new(false, "INVALID_REAR_ACTION_OUTCOME")
    end
    return value
end

-- Every physical move retries only its planned edge. The checked attempt
-- owns fuel admission and pending-action/pose commits on each try.
move = function(movement)
    local rearFailure
    local function detect()
        if movement == "up" then return turtle.detectUp() end
        if movement == "down" then return turtle.detectDown() end
        if movement == "back" then
            local detected, outcome = atRear(turtle.detect)
            if detected == nil then
                rearFailure = outcome
                return true
            end
            return detected
        end
        return turtle.detect()
    end
    local function clear()
        if rearFailure then return rearFailure end
        local checked, pressure, occupied = pcall(Pressure.reached,
            turtle, itemConfig.inventory.returnThreshold)
        if not checked then
            return Result.new(false, "INVENTORY_PRESSURE_CHECK_FAILED")
        end
        if pressure ~= false then
            return Result.new(false, "INVENTORY_CRITICAL",
                "Blocked route needs digging while inventory is under pressure", { occupied = occupied })
        end
        if movement == "up" then return digUp() end
        if movement == "down" then return digDown() end
        if movement == "back" then
            local outcome, errorResult = atRear(digForward)
            return outcome or errorResult
        end
        return digForward()
    end
    local function attack()
        if movement == "back" then
            local outcome, errorResult = atRear(turtle.attack)
            return errorResult or outcome
        end
        local action = movement == "up" and turtle.attackUp
            or movement == "down" and turtle.attackDown or turtle.attack
        if type(action) ~= "function" then
            return Result.new(false, "ENTITY_BLOCKED", "No attack API for blocked movement")
        end
        return action()
    end
    local result = ForwardRecovery.run({
        move = function() return attemptMove(movement) end,
        detect = detect,
        inspect = movement == "back" and nil or (movement == "up" and turtle.inspectUp
            or movement == "down" and turtle.inspectDown or turtle.inspect),
        digClear = clear,
        attack = attack,
        warn = function() print("WARNING: Entity blocks movement; moving away will let mining continue.") end,
        wait = function() sleep(itemConfig.safety.retryDelay) end,
        maxMoveRetries = itemConfig.safety.moveRetries,
        maxEntityRetries = itemConfig.safety.entityRetries,
    })
    if result.ok then return true, result end
    return false, result
end

local function paveDown()
    local result = Paving.tryDown(itemConfig, turtle, SlotGuard, ItemPolicy)
    if result.placed then stats:add("blocks_placed", 1) end
    if result.code == "PAVING_MATERIAL_UNAVAILABLE" then
        print("WARNING: No allowed paving material is available; continuing without paving.")
    elseif result.code == "PAVING_PLACE_FAILED" then
        print("WARNING: Floor paving failed; continuing without optional paving.")
    elseif not result.ok then
        print("ERROR: " .. result.code)
    end
    return result
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

local checkedMoveForRoute, checkedTurnForRoute

local function travelRecordedRoute(targetPose)
    local arrived, outcome = RouteHome.run({
        pose = pos,
        route = knownRoute,
        targetPose = targetPose,
        homeFacing = targetPose.facing,
        move = checkedMoveForRoute,
        turn = checkedTurnForRoute,
    })
    if outcome.ok ~= true then return false, outcome.code end
    pos = arrived
    return true, outcome.code
end

local function travelStairRoute(targetPose)
    local routes = checkpoint:floorLandings()
    local serviceFloor = activeFloor
    if type(serviceFloor) ~= "number" or serviceFloor < 1 or not routes[serviceFloor] then
        return travelRecordedRoute(targetPose)
    end
    local activeLanding = routes[serviceFloor].landing
    if targetPose.x == 0 and targetPose.y == 0 and targetPose.z == 0 then
        if pos.x ~= activeLanding.x or pos.y ~= activeLanding.y
            or pos.z ~= activeLanding.z or pos.facing ~= activeLanding.facing then
            return travelRecordedRoute(targetPose)
        end
        for floor = serviceFloor, 1, -1 do
            local route = routes[floor]
            if not route then return false, "LANDING_ROUTE_INVALID" end
            if not (pos.x == route.landing.x and pos.y == route.landing.y
                and pos.z == route.landing.z and pos.facing == route.landing.facing) then
                local reached, routeOutcome = travelRecordedRoute(route.landing)
                if not reached then return false, routeOutcome end
            end
            local returned, outcome = StairRoute.returnToSurface({
                pose = pos, route = route, move = checkedMoveForRoute, turn = checkedTurnForRoute,
            })
            if outcome.ok ~= true then return false, outcome.code end
            pos = returned
        end
        return pos.x == targetPose.x and pos.y == targetPose.y and pos.z == targetPose.z
            and pos.facing == targetPose.facing, "STAIRS_SURFACE_RESTORED"
    end

    local current = pos
    if targetPose.x ~= activeLanding.x or targetPose.y ~= activeLanding.y
        or targetPose.z ~= activeLanding.z or targetPose.facing ~= activeLanding.facing
        or pos.x ~= activeLanding.x or pos.y ~= activeLanding.y
        or pos.z ~= activeLanding.z or pos.facing ~= activeLanding.facing then
        return travelRecordedRoute(targetPose)
    end
    for floor = serviceFloor, 1, -1 do
        local route = routes[floor]
        if not route then return false, "LANDING_ROUTE_INVALID" end
        if not (current.x == route.landing.x and current.y == route.landing.y
            and current.z == route.landing.z and current.facing == route.landing.facing) then
            local reached, routeOutcome = travelRecordedRoute(route.landing)
            if not reached then return false, routeOutcome end
        end
        local returned, outcome = StairRoute.returnToSurface({
            pose = current, route = route, move = checkedMoveForRoute, turn = checkedTurnForRoute,
        })
        if outcome.ok ~= true then return false, outcome.code end
        current = returned
        pos = returned
    end
    local resumed, outcome = StairRoute.resumeToLanding({
        pose = current, floor = serviceFloor, routes = routes, move = checkedMoveForRoute,
    })
    if outcome.ok ~= true then return false, outcome.code end
    pos = resumed
    return travelRecordedRoute(targetPose)
end

local inventoryService = InventoryService.new({
    turtle = turtle,
    config = config,
    itemConfig = itemConfig,
    pose = function() return pos end,
    checkpoint = function() return checkpoint end,
    progress = function() return checkpoint and checkpoint:resumeCheckpoint().progress end,
    route = function() return knownRoute end,
    configSnapshot = configSnapshot,
    turnToFacing = turnToFacing,
    travel = travelStairRoute,
    resupply = function(savedPose, route)
        local origin = { x = 0, y = 0, z = 0, facing = 0 }
        local path, pathCode = RouteHome.path(route, savedPose, nil, origin)
        if not path then return { ok = false, code = pathCode } end
        local requiredFuel = ResumeCommitment.targetFuelForTrips(
            #path, #path, config.fuel_reserve, 1)
        if not requiredFuel then return { ok = false, code = "INVALID_RESUME_COMMITMENT" } end
        return Resupply.run({
            turtle = turtle,
            itemConfig = itemConfig,
            targetFuel = requiredFuel,
            torchTarget = config.supplies.torchTarget,
            minimumTorches = config.supplies.minimumTorchesToDepart,
        })
    end,
    safeForward = safeForward,
    up = up,
    down = down,
    report = function(message) print("  " .. message) end,
    reportError = function(message) print("ERROR: " .. message) end,
})
local inventoryPressureReached = inventoryService.pressureReached
local serviceInventoryRaw = inventoryService.serviceIfNeeded
local function torchCount()
    local count = 0
    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)
        if detail then
            for _, itemName in ipairs(config.lighting.itemNames) do
                if detail.name == itemName then
                    count = count + turtle.getItemCount(slot)
                    break
                end
            end
        end
    end
    return count
end

local function serviceInventoryIfFull()
    -- These calls occur only at persisted logical checkpoints, before the next
    -- bounded work unit. Refill before a scheduled wall placement can fail.
    local lowTorchStock = config.features.torches and config.lighting.enabled
        and torchCount() < config.supplies.minimumTorchesToDepart
    local serviced, code = serviceInventoryRaw(lowTorchStock == true)
    if serviced and code == "SERVICE_COMPLETE" then stats:add("service_trips", 1) end
    return serviced
end

local function prepareStartupSupplies()
    local entryMoves = config.mining.surfaceEntryLength
    local targetFuel, fuelCode = ResumeCommitment.targetFuelForTrips(
        entryMoves, entryMoves, config.fuel_reserve, 1)
    if not targetFuel then return false, fuelCode or "INVALID_RESUME_COMMITMENT" end

    local homeFacing = pos.facing
    local supplyFacing = (homeFacing + 3) % 4
    local faced, faceOutcome = turnToFacing(supplyFacing)
    if not faced then return false, faceOutcome.code or "SUPPLY_FACING_FAILED" end

    local found, block = turtle.inspect()
    if found ~= true or not block or not Chest.acceptsBlock(block.name, config.base) then
        local restored, restoreOutcome = turnToFacing(homeFacing)
        if not restored then return false, restoreOutcome.code or "POSITION_ERROR" end
        return false, "NO_SUPPLY_CHEST"
    end

    local torchesEnabled = config.features.torches and config.lighting.enabled
    local supplied = Resupply.run({
        turtle = turtle,
        itemConfig = itemConfig,
        targetFuel = targetFuel,
        torchTarget = torchesEnabled and config.supplies.torchTarget or 0,
        minimumTorches = torchesEnabled and config.supplies.minimumTorchesToDepart or 0,
    })
    local restored, restoreOutcome = turnToFacing(homeFacing)
    if not restored then return false, restoreOutcome.code or "POSITION_ERROR" end
    if type(supplied) ~= "table" or supplied.ok ~= true then
        return false, type(supplied) == "table" and supplied.code or "RESUPPLY_FAILED"
    end
    return true, "STARTUP_SUPPLIES_READY"
end

local function serviceBeforeVeinSeed()
    local allowed, code = PressureGate.beforeDig(inventoryPressureReached, function()
        local serviced, serviceCode = serviceInventoryRaw()
        if serviced and serviceCode == "SERVICE_COMPLETE" then stats:add("service_trips", 1) end
        return serviced, serviceCode
    end)
    return allowed, code
end
-- ============================================================================
-- VEIN MINING
-- ============================================================================

local veinInventoryPressureReached = false

local function copyCurrentPose()
    return { x = pos.x, y = pos.y, z = pos.z, facing = pos.facing }
end

local function saveVeinState(veinState)
    if not checkpoint then
        persistenceError = "STATE_NOT_INITIALIZED"
        return false
    end
    local saved, code
    if veinMovementCommitPending then
        saved, code = checkpoint:commitVeinAction(pos, knownRoute, configSnapshot(), veinState)
        if saved then veinMovementCommitPending = false end
    else
        saved, code = checkpoint:setVein(veinState, pos, knownRoute, configSnapshot())
    end
    if not saved then persistenceError = code or "STATE_WRITE_FAILED" end
    return saved
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
            -- The reference vein routine consumed a boolean from digForward/
            -- digUp/digDown. The safe helpers now return typed Result tables,
            -- while VeinTraversal deliberately accepts only literal true.
            -- Adapt the result here so a successfully dug ore is entered.
            local outcome
            if direction == "up" then outcome = digUp()
            elseif direction == "down" then outcome = digDown()
            else outcome = digForward() end
            return type(outcome) == "table" and outcome.ok == true
                and type(outcome.dug) == "number" and outcome.dug > 0
        end,
        move = function(direction)
            local moved = movements[direction]
            if not moved then return false end
            deferVeinMovementCommit = true
            local result = moved()
            deferVeinMovementCommit = false
            return result
        end,
        canContinue = function(target)
            -- The checked movement wrapper also enforces this commitment. Do
            -- the same admission before digging so a candidate is not removed
            -- from the world when refuelling could have made it safe.
            return RouteFuelPolicy.canExplore({
                pose = pos, target = target, route = knownRoute,
                reserve = config.fuel_reserve, getFuelLevel = turtle.getFuelLevel,
                refuel = refuel,
            })
        end,
        turn = turn,
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
    end, function(veinState)
        return saveVeinState(veinState)
    end)
    stats:add("ores_mined", result.blocks - 1)
    veinInventoryPressureReached = result.code == "INVENTORY_RETURN"
    if result.code == "VEIN_FUEL_RETURN" then
        return { ok = false, code = "RETURN_REQUIRED", message = "Vein exploration used the available return reserve." }
    end
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

local checkAndMineOre, checkAndMineOreUp, checkAndMineOreDown

checkAndMineOre = function(mainShaftDirection, deferCandidate)
    local hasBlock, data =
        turtle.inspect()

    if hasBlock
        and OreClassifier.isOre(data, config.ore) then

        if deferCandidate then
            local x, y, z = getForwardPosition()
            return Result.new(true, "ORE_CANDIDATE_FOUND"),
                { x = x, y = y, z = z, facing = pos.facing }
        end
        stats:add("veins_found", 1)
        veinInventoryPressureReached = false

        local checkpoint = copyCurrentPose()
        local entryX, entryY, entryZ = getForwardPosition()
        local admitted, admissionCode = serviceBeforeVeinSeed()
        if not admitted then
            return Result.new(false, admissionCode or "INVENTORY_SERVICE_FAILED",
                "Could not service inventory before entering an exposed ore vein")
        end
        local entryState = {
            stage = "entering",
            checkpoint = checkpoint,
            entryPose = { x = entryX, y = entryY, z = entryZ, facing = checkpoint.facing },
            visited = { [checkpoint.x .. "," .. checkpoint.y .. "," .. checkpoint.z] = true },
            frontier = {},
            route = {},
            blocks = 0,
        }
        if not saveVeinState(entryState) then
            return Result.new(false, persistenceError)
        end
        local dug = digForward()
        if not dug.ok then
            return dug
        end
        stats:add("ores_mined", 1)
        if forwardIntoVein() ~= true then
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

checkAndMineOreUp = function(mainShaftDirection, deferCandidate)
    local hasBlock, data =
        turtle.inspectUp()

    if hasBlock
        and OreClassifier.isOre(data, config.ore) then

        if deferCandidate then
            return Result.new(true, "ORE_CANDIDATE_FOUND"),
                { x = pos.x, y = pos.y + 1, z = pos.z, facing = pos.facing }
        end
        stats:add("veins_found", 1)
        veinInventoryPressureReached = false

        local checkpoint = copyCurrentPose()
        local admitted, admissionCode = serviceBeforeVeinSeed()
        if not admitted then
            return Result.new(false, admissionCode or "INVENTORY_SERVICE_FAILED",
                "Could not service inventory before entering an exposed ore vein")
        end
        local entryState = {
            stage = "entering",
            checkpoint = checkpoint,
            entryPose = { x = checkpoint.x, y = checkpoint.y + 1,
                z = checkpoint.z, facing = checkpoint.facing },
            visited = { [checkpoint.x .. "," .. checkpoint.y .. "," .. checkpoint.z] = true },
            frontier = {},
            route = {},
            blocks = 0,
        }
        if not saveVeinState(entryState) then
            return Result.new(false, persistenceError)
        end
        local dug = digUp()
        if not dug.ok then
            return dug
        end
        stats:add("ores_mined", 1)
        deferVeinMovementCommit = true
        local entered = up()
        deferVeinMovementCommit = false
        if entered ~= true then
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

checkAndMineOreDown = function(mainShaftDirection, deferCandidate)
    local hasBlock, data =
        turtle.inspectDown()

    if hasBlock
        and OreClassifier.isOre(data, config.ore) then

        if deferCandidate then
            return Result.new(true, "ORE_CANDIDATE_FOUND"),
                { x = pos.x, y = pos.y - 1, z = pos.z, facing = pos.facing }
        end
        stats:add("veins_found", 1)
        veinInventoryPressureReached = false

        local checkpoint = copyCurrentPose()
        local admitted, admissionCode = serviceBeforeVeinSeed()
        if not admitted then
            return Result.new(false, admissionCode or "INVENTORY_SERVICE_FAILED",
                "Could not service inventory before entering an exposed ore vein")
        end
        local entryState = {
            stage = "entering",
            checkpoint = checkpoint,
            entryPose = { x = checkpoint.x, y = checkpoint.y - 1,
                z = checkpoint.z, facing = checkpoint.facing },
            visited = { [checkpoint.x .. "," .. checkpoint.y .. "," .. checkpoint.z] = true },
            frontier = {},
            route = {},
            blocks = 0,
        }
        if not saveVeinState(entryState) then
            return Result.new(false, persistenceError)
        end
        local dug = digDown()
        if not dug.ok then
            return dug
        end
        stats:add("ores_mined", 1)
        deferVeinMovementCommit = true
        local entered = down()
        deferVeinMovementCommit = false
        if entered ~= true then
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

    local moved, movementOutcome = forward()
    if not moved then
        print("ERROR: " .. movementOutcome.code .. " - "
            .. tostring(movementOutcome.message or "Forward movement recovery failed"))
        return movementOutcome
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
        pose = function() return copyCurrentPose() end,
        candidateQueue = function(anchor) return OreCandidateQueue.new(anchor) end,
        drainCandidates = function(queue, anchor)
            return queue.drain(pos, function(candidate)
                local dx, dz = 0, 0
                if anchor.facing == 0 then dz = -1
                elseif anchor.facing == 1 then dx = 1
                elseif anchor.facing == 2 then dz = 1
                else dx = -1 end
                local rx, ry, rz = candidate.x - anchor.x,
                    candidate.y - anchor.y, candidate.z - anchor.z
                local direction
                if rx == 0 and ry == 1 and rz == 0 then direction = "up"
                elseif rx == 0 and ry == -1 and rz == 0 then direction = "down"
                elseif ry == 0 and rx == -dx and rz == -dz then direction = "left"
                elseif ry == 0 and rx == dx and rz == dz then direction = "right" end
                if not direction then return Result.new(false, "ORE_CANDIDATE_ROUTE_INVALID") end
                local mined
                if direction == "up" then mined = checkAndMineOreUp("up")
                elseif direction == "down" then mined = checkAndMineOreDown("down")
                else
                    local turned = direction == "left" and turnLeft() or turnRight()
                    if turned ~= true then return Result.new(false, "TURN_FAILED") end
                    mined = checkAndMineOre("forward")
                    local restored = direction == "left" and turnRight() or turnLeft()
                    if restored ~= true then return Result.new(false, "TURN_FAILED") end
                end
                if mined == true or type(mined) == "table" and mined.ok == true then return true end
                return type(mined) == "table" and mined
                    or Result.new(false, "ORE_CANDIDATE_EXECUTION_FAILED")
            end)
        end,
        scan = function(direction)
            if direction == "left" then
                if turnLeft() ~= true then return Result.new(false, "TURN_FAILED") end
                local scanned, candidate = checkAndMineOre("forward", true)
                if turnRight() ~= true then return Result.new(false, "TURN_FAILED") end
                return scanned, candidate
            elseif direction == "right" then
                if turnRight() ~= true or turnRight() ~= true then return Result.new(false, "TURN_FAILED") end
                local scanned, candidate = checkAndMineOre("forward", true)
                if turnLeft() ~= true or turnLeft() ~= true then return Result.new(false, "TURN_FAILED") end
                return scanned, candidate
            elseif direction == "down" then
                return checkAndMineOreDown(direction, true)
            elseif direction == "up" then
                return checkAndMineOreUp(direction, true)
            end
            return Result.new(false, "INVALID_SCAN_DIRECTION")
        end,
    })
    if not result.ok then print("ERROR: " .. result.code) end
    return result.ok
end

local function placeTunnelTorch(outboundFacing, distance, force, routeId)
    if not config.features.torches or not config.lighting.enabled
        or (not force and distance % config.lighting.tunnelInterval ~= 0) then
        return true
    end
    local key = string.format("floor-%d-%s-%d", activeFloor, routeId or "main", distance)
    if checkpoint and checkpoint:hasTorchPlacement(key) then return true end
    local selected = SlotGuard.run(turtle, function()
        local slot
        for index = 1, 16 do
            local detail = turtle.getItemDetail(index)
            local isTorch = false
            if detail then
                for _, itemName in ipairs(config.lighting.itemNames) do
                    if detail.name == itemName then isTorch = true break end
                end
            end
            if isTorch
                and turtle.getItemCount(index) > 0 then
                slot = index
                break
            end
        end
        if not slot or turtle.select(slot) ~= true then
            if not slot then return Result.new(false, "NO_TORCHES", nil, { skippable = true }) end
            return Result.new(false, "TORCH_SELECT_FAILED")
        end
        return Lighting.placeRight({
            pose = copyCurrentPose(),
            outboundFacing = outboundFacing,
            poseNow = copyCurrentPose,
            turn = checkedTurnForRoute,
            -- Floor tunnel walls need a niche; the stair passage is already clear.
            dig = function() return digForward(true) end,
            place = function()
                local called, placed = pcall(turtle.place)
                if not called or placed ~= true then
                    return Result.new(false, "TORCH_PLACE_FAILED")
                end
                stats:add("torches_placed", 1)
                return Result.new(true, "TORCH_PLACED")
            end,
        })
    end)
    if not selected.ok or type(selected.value) ~= "table" or selected.value.ok ~= true then
        local code = selected.ok and selected.value and selected.value.code or selected.code
        if selected.ok and type(selected.value) == "table"
            and selected.value.skippable == true then
            print("WARNING: Skipped right-wall torch: " .. tostring(code))
            return true
        end
        print("ERROR: " .. tostring(code or "LIGHTING_FAILED"))
        return false
    end
    if checkpoint then
        local saved, saveCode = checkpoint:recordTorchPlacement(key, pos, knownRoute, configSnapshot())
        if not saved then
            persistenceError = saveCode
            markFatal(saveCode or "STATE_WRITE_FAILED")
            return false
        end
    end
    return true
end

local function placeStairTorch(slicePose)
    if not config.features.torches or not config.lighting.enabled then return true end
    local key = string.format("floor-%d-stair-%d", activeFloor, -slicePose.y)
    if checkpoint and checkpoint:hasTorchPlacement(key) then return true end
    local originalFacing = slicePose.facing
    local sideCell = Lighting.rightSide(slicePose, originalFacing)
    local sideHeading = sideCell and sideCell.facing
    if not sideCell or sideHeading ~= (originalFacing + 1) % 4 then
        print("ERROR: LIGHTING_INVALID_FRAME")
        return false
    end
    local function restoreCenter()
        local current = copyCurrentPose()
        if current.x ~= slicePose.x or current.y ~= slicePose.y or current.z ~= slicePose.z then
            return false, Result.new(false, "LIGHTING_POSE_MISMATCH")
        end
        if current.facing ~= originalFacing then
            local restored, outcome = Turn.face(current, originalFacing, checkedTurnForRoute)
            if not restored then return false, outcome end
        end
        return copyCurrentPose().facing == originalFacing, Result.new(true, "STAIR_TORCH_RESTORED")
    end

    local selected = SlotGuard.run(turtle, function()
        local slot
        for index = 1, 16 do
            local detail = turtle.getItemDetail(index)
            if detail then
                for _, itemName in ipairs(config.lighting.itemNames) do
                    if detail.name == itemName and turtle.getItemCount(index) > 0 then
                        slot = index
                        break
                    end
                end
            end
            if slot then break end
        end
        if not slot then return Result.new(false, "NO_TORCHES", nil, { skippable = true }) end
        if turtle.select(slot) ~= true then return Result.new(false, "TORCH_SELECT_FAILED") end
        return Lighting.placeRight({
            pose = copyCurrentPose(), outboundFacing = originalFacing,
            poseNow = copyCurrentPose,
            turn = checkedTurnForRoute,
            alreadyClear = true,
            place = function()
                local called, placed = pcall(turtle.place)
                if not called or placed ~= true then
                    return Result.new(false, "TORCH_PLACE_FAILED")
                end
                stats:add("torches_placed", 1)
                return Result.new(true, "TORCH_PLACED")
            end,
        })
    end)
    local restored, restoreResult = restoreCenter()
    if not restored then
        print("ERROR: " .. tostring(restoreResult and restoreResult.code or "STAIR_TORCH_RESTORE_FAILED"))
        return false
    end
    local placed = selected.ok and type(selected.value) == "table" and selected.value.ok == true
    if not placed then
        local code = selected.ok and selected.value and selected.value.code or selected.code
        if selected.ok and type(selected.value) == "table"
            and selected.value.skippable == true then
            print("WARNING: Skipped stair torch: " .. tostring(code))
            return true
        end
        print("ERROR: " .. tostring(code or "STAIR_TORCH_FAILED"))
        return false
    end
    if checkpoint then
        local saved, saveCode = checkpoint:recordTorchPlacement(key, pos, knownRoute, configSnapshot())
        if not saved then
            persistenceError = saveCode
            markFatal(saveCode or "STATE_WRITE_FAILED")
            return false
        end
    end
    return true
end

local function mineBranch(length, branchPair, side, mainOffset, mainSide,
    resumeDistance, resumePhase)
    local savedLanding = checkpoint:floorLanding(activeFloor)
    local gridLanding = savedLanding and {
        floor = savedLanding.floor,
        pose = savedLanding.landing,
    } or nil
    local grid, gridStatus = FloorGrid.new({ x = 0, y = 0, z = 0, facing = 0 }, 0,
        gridLanding, config.mining.stairStepsPerFloor,
        config.mining.firstFloorDepthOffset)
    if not grid then
        print("ERROR: " .. gridStatus.code)
        return false, gridStatus
    end
    local junctionPose = grid.junction(mainOffset, mainSide)
    local branch, branchStatus = grid.branch(junctionPose, side)
    if not branch then
        print("ERROR: " .. branchStatus.code)
        return false, branchStatus
    end
    local traversal, traversalStatus = BranchTraversal.new(branch, length)
    if not traversal then
        print("ERROR: " .. traversalStatus.code)
        return false, traversalStatus
    end

    local firstIndex = (resumeDistance or 0) + 1
    local resumePose
    if not resumePhase or resumePhase == "branch_outbound_lower" then
        resumePose = traversal.outboundPose(resumeDistance or 0)
    elseif resumePhase == "branch_turnaround" then
        resumePose = traversal.outboundPose(length)
    elseif resumePhase == "branch_upper_return" then
        resumePose = traversal.upperReturnPose(length - resumeDistance)
    elseif resumePhase == "branch_return_to_junction" then
        resumePose = traversal.upperReturnPose(0)
    end
    if not resumePose or pos.x ~= resumePose.x or pos.y ~= resumePose.y
        or pos.z ~= resumePose.z or pos.facing ~= resumePose.facing then
        return false, { ok = false, code = "BRANCH_RESUME_POSE_MISMATCH",
            actual = copyCurrentPose(), expected = resumePose }
    end
    local outboundResult = resumePhase and resumePhase ~= "branch_outbound_lower"
        and { ok = true, code = "BRANCH_OUTBOUND_ALREADY_COMPLETE", completed = length, requested = length }
        or BranchProgress.run(length, function(i)
        local cursor = MiningCursor.branch(branchPair, side, "branch_outbound_lower",
            i - 1, mainOffset, "mine_branch_cell", activeFloor, mainSide)
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
            local turned = turnLeft()
            if turned ~= true then return { ok = false, code = "TURN_FAILED" } end
            local scanned = checkAndMineOre()
            if not scanned.ok then return scanned end
            turned = turnRight()
            if turned ~= true then return { ok = false, code = "TURN_FAILED" } end

            turned = turnRight()
            if turned ~= true then return { ok = false, code = "TURN_FAILED" } end
            local scanned = checkAndMineOre()
            if not scanned.ok then return scanned end
            turned = turnLeft()
            if turned ~= true then return { ok = false, code = "TURN_FAILED" } end

            local scanned = checkAndMineOreDown()
            if not scanned.ok then return scanned end
        end

        -- The shaft's right side is defined by its outbound heading, even
        -- though the same helper is also used later while facing back home.
        local torchRoute = (mainSide == "right" and "" or "left-main-")
            .. side .. "-shaft-" .. mainOffset
        if not placeTunnelTorch(branch.facing, i, false, torchRoute) then
            return { ok = false, code = "BRANCH_TORCH_FAILED",
                message = "Unable to place the scheduled right-wall torch" }
        end

        if not serviceInventoryIfFull() then
            return { ok = false, code = "INVENTORY_SERVICE_FAILED", message = "Inventory service failed during branch mining" }
        end
        return true
    end, firstIndex)

    if not outboundResult.ok then
        print("ERROR: " .. outboundResult.code .. " (completed "
            .. outboundResult.completed .. "/" .. outboundResult.requested .. ")")
        return false, outboundResult
    end

    if not resumePhase or resumePhase == "branch_outbound_lower" then
        local turnaroundCursor = MiningCursor.branch(branchPair, side, "branch_turnaround",
            length, mainOffset, "prepare_branch_return", activeFloor, mainSide)
        if not persistMiningCursor(turnaroundCursor) then return false end
    end

    if (not resumePhase or resumePhase == "branch_outbound_lower"
        or resumePhase == "branch_turnaround") and config.base.separateBulk ~= true then
        local ejected = BranchEjection.run(turtle, itemConfig)
        if not ejected.ok then
            print("ERROR: " .. ejected.code .. " - " .. (ejected.message or "branch-end ejection failed"))
            return false, ejected
        end
    end

    if not resumePhase or resumePhase == "branch_outbound_lower"
        or resumePhase == "branch_turnaround" then
        local expectedEndpoint = traversal.outboundPose(length)
        if not expectedEndpoint or pos.x ~= expectedEndpoint.x or pos.y ~= expectedEndpoint.y
            or pos.z ~= expectedEndpoint.z or pos.facing ~= expectedEndpoint.facing then
            return false, { ok = false, code = "BRANCH_POSE_MISMATCH" }
        end
    end

    if not resumePhase or resumePhase == "branch_outbound_lower"
        or resumePhase == "branch_turnaround" then
        local clearedAbove = digUp()
        if not clearedAbove.ok then return false, clearedAbove end
    end

    do

        if not resumePhase or resumePhase == "branch_outbound_lower"
            or resumePhase == "branch_turnaround" then
            if up() ~= true then return false, { ok = false, code = "BRANCH_RETURN_MOVE_FAILED" } end
            if turnRight() ~= true or turnRight() ~= true then
                return false, { ok = false, code = "TURN_FAILED" }
            end
        end

        local firstReturnIndex = resumePhase == "branch_upper_return"
            and (length - resumeDistance + 1) or 1
        local lastReturnIndex = resumePhase == "branch_return_to_junction" and 0 or length
        for i = firstReturnIndex, lastReturnIndex do

            local returnCursor = MiningCursor.branch(branchPair, side, "branch_upper_return",
                length - i + 1, mainOffset, "scan_and_return_branch_cell",
                activeFloor, mainSide)
            if not persistMiningCursor(returnCursor) then return false end

            if not serviceInventoryIfFull() then
                return false
            end

            if config.vein_mine then
                if turnLeft() ~= true then return false, { ok = false, code = "TURN_FAILED" } end
                local scanned = checkAndMineOre()
                if not scanned.ok then return false, scanned end
                if turnRight() ~= true then return false, { ok = false, code = "TURN_FAILED" } end

                if turnRight() ~= true then return false, { ok = false, code = "TURN_FAILED" } end
                scanned = checkAndMineOre()
                if not scanned.ok then return false, scanned end
                if turnLeft() ~= true then return false, { ok = false, code = "TURN_FAILED" } end

                scanned = checkAndMineOreUp()
                if not scanned.ok then return false, scanned end
            end

            if not serviceInventoryIfFull() then
                return false
            end

            local advanced, movementOutcome = forward()
            if not advanced then
                print("ERROR: " .. movementOutcome.code .. " during upper branch sweep")
                return false, movementOutcome
            end
        end

        if not resumePhase or resumePhase ~= "branch_return_to_junction" then
            local junctionCursor = MiningCursor.branch(branchPair, side,
                "branch_return_to_junction", 0, mainOffset, "descend_to_junction",
                activeFloor, mainSide)
            if not persistMiningCursor(junctionCursor) then return false end
        end

        if down() ~= true then return false, { ok = false, code = "BRANCH_RETURN_MOVE_FAILED" } end

    end

    local expectedJunction = traversal.canonicalJunctionPose()
    if pos.x ~= expectedJunction.x or pos.y ~= expectedJunction.y or pos.z ~= expectedJunction.z
        or pos.facing ~= (branch.facing + 2) % 4 then
        return false, { ok = false, code = "BRANCH_JUNCTION_MISMATCH",
            actual = copyCurrentPose(), expected = expectedJunction }
    end
    local restored, restoreResult = turn(side == "left" and "left" or "right")
    if restored ~= true then
        return false, { ok = false, code = "BRANCH_FACING_RESTORE_FAILED",
            cause = type(restoreResult) == "table" and restoreResult.code or restoreResult }
    end
    if pos.x ~= expectedJunction.x or pos.y ~= expectedJunction.y
        or pos.z ~= expectedJunction.z or pos.facing ~= expectedJunction.facing then
        return false, { ok = false, code = "BRANCH_JUNCTION_MISMATCH",
            actual = copyCurrentPose(), expected = expectedJunction }
    end
    return true
end

-- ============================================================================
-- FUEL STATUS
-- ============================================================================

local function printFuelStatus(branch_num)
    local level =
        turtle.getFuelLevel()

    if FuelLevel.isUnlimited(level) then
        print("  [Fuel] Level: unlimited | Route admission: enabled")
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

local function returnToKnownHome(returnTarget)
    local homePose, outcome = RouteHome.run({
        pose = pos,
        route = knownRoute,
        targetPose = returnTarget,
        homeFacing = returnTarget and returnTarget.facing or 0,
        move = function(direction)
            local moved, reason = move(direction)
            if moved then return pos, Result.new(true, "MOVE_COMMITTED") end
            if type(reason) == "table" and reason.ok == false then return pos, reason end
            return pos, lastMovementOutcome or Result.new(false, "RETURN_MOVE_FAILED", tostring(reason))
        end,
        turn = function(direction)
            local turned, reason = turn(direction)
            if turned then return pos, Result.new(true, "TURN_COMMITTED") end
            if type(reason) == "table" and reason.ok == false then return pos, reason end
            return pos, Result.new(false, "RETURN_TURN_FAILED", tostring(reason))
        end,
    })
    if outcome.ok ~= true then
        print("ERROR: unable to return along the recorded route: " .. tostring(outcome.code))
        return false, outcome
    end
    pos = homePose
    return true, outcome
end

checkedMoveForRoute = function(direction)
    local moved, reason = move(direction)
    if moved then return pos, Result.new(true, "MOVE_COMMITTED") end
    if type(reason) == "table" and reason.ok == false then return pos, reason end
    return pos, lastMovementOutcome or Result.new(false, "MOVE_FAILED", tostring(reason))
end

checkedTurnForRoute = function(direction)
    local turned, reason = turn(direction)
    if turned then return pos, Result.new(true, "TURN_COMMITTED") end
    if type(reason) == "table" and reason.ok == false then return pos, reason end
    return pos, Result.new(false, "TURN_FAILED", tostring(reason))
end

local function clearForStair(direction)
    if direction == "forward" then return digForward() end
    if direction == "up" then return digUp() end
    if direction == "down" then return digDown() end
    return Result.new(false, "INVALID_CLEAR_DIRECTION")
end

local function saveStairCursor(context)
    local cursor = MiningCursor.stairs(context.floor, context.stairStep, context.action)
    local saved, code = persistMiningCursor(cursor)
    if not saved then return false, Result.new(false, code or "STATE_WRITE_FAILED") end
    return true, Result.new(true, "STAIR_CURSOR_SAVED")
end

local function descendToLanding(floor)
    local steps = require("src.core.stair_geometry").stepsForFloor(
        config.mining.stairStepsPerFloor, config.mining.firstFloorDepthOffset, floor)
    if not steps then
        return pos, Result.new(false, "INVALID_STAIR_STEPS")
    end
    stairRouteAction = true
    local landingPose, outcome = StairRoute.descend({
        pose = pos,
        floor = floor,
        steps = steps,
        alreadyAtFrontLanding = floor > 1,
        move = checkedMoveForRoute,
        turn = checkedTurnForRoute,
        clear = clearForStair,
        stairTorchInterval = config.lighting.stairInterval,
        placeStairTorch = config.lighting.skipLandingSlice and function(slicePose, step)
                local placed = placeStairTorch(slicePose)
                return Result.new(placed, placed and "TORCH_PLACED" or "STAIR_TORCH_FAILED")
            end or nil,
        beforeEntry = saveStairCursor,
        beforeStep = saveStairCursor,
        beforeLanding = function(context)
            context.stairStep = context.stairStep + 1
            return saveStairCursor(context)
        end,
        saveProgress = function(progress)
            stats:add("stair_slices_completed", 1)
            local nextCursor = MiningCursor.stairs(
                progress.floor, progress.nextStep, progress.nextAction)
            local saved, code = persistMiningCursor(nextCursor)
            if not saved then
                return false, Result.new(false, code or "STATE_WRITE_FAILED",
                    "Could not persist the next stairs action.")
            end
            return true, Result.new(true, "STAIR_PROGRESS_RECORDED", nil, progress)
        end,
        afterStep = function()
            local serviced, code = serviceInventoryIfFull()
            if serviced ~= true then
                return false, Result.new(false, code or "INVENTORY_SERVICE_FAILED",
                    "Inventory service failed after a completed stairs slice.")
            end
            return true, Result.new(true, "STAIR_CHECKPOINT_READY")
        end,
        prepareLanding = function(rearPose)
            return FloorLanding.prepare({
                pose = rearPose,
                clear = clearForStair,
                move = checkedMoveForRoute,
                turn = checkedTurnForRoute,
            })
        end,
        saveLanding = function(route)
            local saved, code = checkpoint:recordFloorLanding(
                route, pos, knownRoute, configSnapshot())
            if not saved then return false, Result.new(false, code or "STATE_WRITE_FAILED") end
            return true, Result.new(true, "LANDING_SAVED")
        end,
    })
    stairRouteAction = nil
    if outcome.ok ~= true then return landingPose, outcome end
    if pos.x ~= landingPose.x or pos.y ~= landingPose.y
        or pos.z ~= landingPose.z or pos.facing ~= landingPose.facing then
        return pos, Result.new(false, "POSITION_ERROR", "Stair route and committed coordinator pose diverged.")
    end
    return landingPose, outcome
end

-- ============================================================================
-- MAIN MINING PATTERN
-- ============================================================================

local function executeMining(returnTarget, deferSummary, resumeCursor, requestedMainSide)

    local mainSide = requestedMainSide or (resumeCursor and resumeCursor.mainSide) or "right"
    if mainSide ~= "right" and mainSide ~= "left" then
        persistenceError = "INVALID_MAIN_SIDE"
        return false
    end
    if resumeCursor and (resumeCursor.mainSide or "right") ~= mainSide then
        persistenceError = "MAIN_SIDE_CURSOR_MISMATCH"
        return false
    end

    local resumeStart
    if resumeCursor then
        local code
        if resumeCursor.phase == "main_side_start" then
            resumeStart = { branch = 1, step = 1, mainSide = mainSide }
        elseif resumeCursor.phase == "main_side_return" then
            resumeStart = { branch = config.num_branches + 1, step = 1,
                mainSide = mainSide }
        elseif resumeCursor.phase == "main_shaft" then
            local MainShaftResume = require("src.mining.main_shaft_resume")
            resumeStart, code = MainShaftResume.start(
                resumeCursor, config.num_branches, config.spacing)
        elseif resumeCursor.phase == "junction" then
            local JunctionResume = require("src.mining.junction_resume")
            resumeStart, code = JunctionResume.start(
                resumeCursor, config.num_branches, config.spacing)
        elseif resumeCursor.phase == "branch_outbound_lower"
            or resumeCursor.phase == "branch_turnaround"
            or resumeCursor.phase == "branch_upper_return"
            or resumeCursor.phase == "branch_return_to_junction" then
            local BranchResume = require("src.mining.branch_resume")
            resumeStart, code = BranchResume.start(resumeCursor, config.num_branches,
                config.spacing, config.branch_length)
        else
            code = "CURSOR_RESUME_UNSUPPORTED"
        end
        if not resumeStart then
            persistenceError = code or "MAIN_SHAFT_CURSOR_OUT_OF_RANGE"
            return false
        end
    end

    if not resumeCursor or resumeCursor.phase == "main_side_start" then
        if pos.x ~= returnTarget.x or pos.y ~= returnTarget.y
            or pos.z ~= returnTarget.z then
            persistenceError = "MAIN_SIDE_START_POSE_MISMATCH"
            return false
        end
        if not resumeCursor then
            local startCursor = MiningCursor.mainSideStart(activeFloor, mainSide)
            if not persistMiningCursor(startCursor) then return false end
        end
        local targetFacing = (returnTarget.facing + (mainSide == "right" and 1 or 3)) % 4
        if pos.facing == returnTarget.facing then
            local turned = mainSide == "right" and turnRight() or turnLeft()
            if turned ~= true then
                persistenceError = "FLOOR_MAIN_TURN_FAILED"
                return false
            end
        elseif pos.facing ~= targetFacing then
            persistenceError = "MAIN_SIDE_START_POSE_MISMATCH"
            return false
        end
        local firstCursor = MiningCursor.mainShaft(1, 1, 0, activeFloor, mainSide)
        if not persistMiningCursor(firstCursor) then return false end
    end

    local startedAt = os.epoch("utc") / 1000

    print("=== Fuel Check ===")
    print("Current fuel: " .. FuelLevel.format(turtle.getFuelLevel()))
    print("Each move checks the recorded route home plus reserve.")

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

    local firstBranch = resumeStart and resumeStart.branch or 1
    for branch = firstBranch, config.num_branches do

        print(Status.phase("MAIN", branch, config.num_branches, mainSide .. " main"))

        local branchResumeHere = resumeStart and branch == firstBranch
            and resumeCursor.phase ~= "main_shaft"
            and resumeCursor.phase ~= "junction"
            and resumeCursor.phase ~= "main_side_start"
        local firstStep = resumeStart and branch == firstBranch and resumeStart.step or 1
        local mainOffsetBeforePair = (branch - 1) * config.spacing
        if not branchResumeHere then
        for step = firstStep, config.spacing do

            local mainCursor = MiningCursor.mainShaft(
                branch, step, mainOffsetBeforePair, activeFloor, mainSide)
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

            local mainDistance = mainOffsetBeforePair + step
            if not placeTunnelTorch(pos.facing, mainDistance, false,
                mainSide == "right" and "main" or "left-main") then return false end

            local nextMainCursor
            if step < config.spacing then
                nextMainCursor = MiningCursor.mainShaft(
                    branch, step + 1, mainOffsetBeforePair, activeFloor, mainSide)
            else
                nextMainCursor = MiningCursor.junction(
                    branch, branch * config.spacing, "turn_to_left_branch",
                    activeFloor, mainSide)
            end
            if not persistMiningCursor(nextMainCursor) then return false end

            if not serviceInventoryIfFull() then
                return false
            end
        end
        end

        print(Status.phase("BRANCH", branch, config.num_branches, "L out"))

        local resumedLeft = branchResumeHere and resumeStart.side == "left"
        local resumedRight = branchResumeHere and resumeStart.side == "right"
        if not resumedRight then
            if not resumedLeft then
                local junctionOffset = branch * config.spacing
                local leftJunctionCursor = MiningCursor.junction(
                    branch, junctionOffset, "turn_to_left_branch", activeFloor, mainSide)
                if not persistMiningCursor(leftJunctionCursor) then return false end
                if turnLeft() ~= true then
                    print("ERROR: LEFT_BRANCH_TURN_FAILED")
                    return false
                end
            end

            local leftMined, leftFailure = mineBranch(config.branch_length, branch, "left",
                branch * config.spacing, mainSide,
                resumedLeft and resumeStart.distance or nil,
                resumedLeft and resumeStart.phase or nil)
            if not leftMined then
                print("ERROR: Left branch mining failed ("
                    .. tostring(type(leftFailure) == "table" and leftFailure.code or leftFailure) .. ")")
                return false
            end
            tryAutoRefuelCoal()
            if not serviceInventoryIfFull() then return false end
        end

        print(Status.phase("BRANCH", branch, config.num_branches, "R out"))

        if not resumedRight then
            if turnRight() ~= true then
                print("ERROR: RIGHT_BRANCH_TURN_FAILED")
                return false
            end
        end

        local rightMined, rightFailure = mineBranch(
            config.branch_length,
            branch,
            "right",
            branch * config.spacing,
            mainSide,
            resumedRight and resumeStart.distance or nil,
            resumedRight and resumeStart.phase or nil
        )
        if not rightMined then
            print("ERROR: Right branch mining failed ("
                .. tostring(type(rightFailure) == "table" and rightFailure.code or rightFailure) .. ")")
            return false
        end

        tryAutoRefuelCoal()

        if not serviceInventoryIfFull() then
            return false
        end

        local mainFacingCursor = MiningCursor.junction(
            branch, branch * config.spacing, "restore_main_facing", activeFloor,
            mainSide)
        if not persistMiningCursor(mainFacingCursor) then return false end

        stats:add("branches_completed", 1)

        local currentFuel =
            turtle.getFuelLevel()

        local fuelStr =
        FuelLevel.format(currentFuel)

        print(Status.branchComplete(branch, config.num_branches, stats:get("blocks_mined"), fuelStr))

        printFuelStatus(branch)

        print("")
    end

    if not resumeCursor or resumeCursor.phase ~= "main_side_return" then
        local returnCursor = MiningCursor.mainSideReturn(activeFloor, mainSide,
            config.num_branches, config.num_branches * config.spacing)
        if not persistMiningCursor(returnCursor) then return false end
    end
    local homeReached, homeOutcome = returnToKnownHome(returnTarget)
    if not homeReached then
        persistenceError = homeOutcome.code or "RETURN_FAILED"
        return false
    end

    if deferSummary then
        print("Floor mining pass complete; returned to its recorded landing.")
        return true
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

    if FuelLevel.isUnlimited(endFuel) then
        print("Ending fuel: unlimited")
    else

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

local function confirmConfiguration()

    print(
        "=== Validated Mining Configuration ==="
    )

    print("")

    for _, tag in ipairs(OreClassifier.missingConfiguredTags(config.ore)) do
        print("WARNING: configured ore tag is absent from the supplied tag registry: " .. tag)
    end

    print("")
    print("Configuration file: config.lua (schema 1)")

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

    print("  Chests: supply left, output right"
        .. (config.base.separateBulk and ", bulk behind" or ", branch-end excess cobblestone ejection"))

    print(
        "  Keeps: configured aggregate supply and backfill quotas"
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

local function executeFloors(firstFloor, resumeCursor)
    local startedAt = os.epoch("utc") / 1000
    firstFloor = firstFloor or 1
    local function mineBothSides(landingPose, cursor)
        local mainSide = cursor and (cursor.mainSide or "right") or "right"
        if not executeMining(landingPose, true, cursor, mainSide) then return false end
        if mainSide == "right" then
            return executeMining(landingPose, true, nil, "left")
        end
        return true
    end
    for floor = firstFloor, config.mining.floorCount do
        activeFloor = floor
        local landingPose
        if resumeCursor and floor == firstFloor
            and resumeCursor.phase == "stairs" and resumeCursor.nextAction == "cross_landing" then
            local prior = checkpoint:floorLanding(floor - 1)
            if not prior or pos.x ~= prior.landing.x or pos.y ~= prior.landing.y
                or pos.z ~= prior.landing.z or pos.facing ~= prior.landing.facing then
                persistenceError = "LANDING_RESUME_UNSUPPORTED"
                return false
            end
            local stairOutcome
            landingPose, stairOutcome = descendToLanding(floor)
            if stairOutcome.ok ~= true then
                persistenceError = stairOutcome.code or "STAIR_DESCENT_FAILED"
                return false
            end
            if not mineBothSides(landingPose) then return false end
            resumeCursor = nil
        elseif resumeCursor and floor == firstFloor then
            local landing = checkpoint:floorLanding(floor)
            if not landing then
                persistenceError = "LANDING_NOT_RECORDED"
                return false
            end
            landingPose = landing.landing
            if (resumeCursor.phase ~= "main_side_start"
                and resumeCursor.phase ~= "main_side_return"
                and resumeCursor.phase ~= "main_shaft" and resumeCursor.phase ~= "junction"
                and resumeCursor.phase ~= "branch_outbound_lower"
                and resumeCursor.phase ~= "branch_turnaround"
                and resumeCursor.phase ~= "branch_upper_return"
                and resumeCursor.phase ~= "branch_return_to_junction")
                or resumeCursor.branchPair > config.num_branches
                or (resumeCursor.phase == "main_shaft" and resumeCursor.offset >= config.spacing)
                or (resumeCursor.phase == "branch_outbound_lower"
                    and resumeCursor.offset >= config.branch_length) then
                persistenceError = resumeCursor.phase == "junction" and "JUNCTION_CURSOR_OUT_OF_RANGE"
                    or (resumeCursor.phase ~= "main_shaft" and "BRANCH_CURSOR_OUT_OF_RANGE")
                    or "MAIN_SHAFT_CURSOR_OUT_OF_RANGE"
                return false
            end
            if not mineBothSides(landingPose, resumeCursor) then return false end
            resumeCursor = nil
        else
            print(string.format("=== Floor %d/%d: stairs descent ===", floor, config.mining.floorCount))
            local stairOutcome
            landingPose, stairOutcome = descendToLanding(floor)
            if stairOutcome.ok ~= true then
                persistenceError = stairOutcome.code or "STAIR_DESCENT_FAILED"
                print("ERROR: " .. tostring(persistenceError))
                return false
            end
            if not mineBothSides(landingPose) then return false end
        end
        if pos.x ~= landingPose.x or pos.y ~= landingPose.y
            or pos.z ~= landingPose.z or pos.facing ~= landingPose.facing then
            persistenceError = "FLOOR_LANDING_NOT_RESTORED"
            return false
        end
        local completedCursor, cursorError = MiningCursor.floorComplete(floor)
        if not completedCursor then
            persistenceError = cursorError or "INVALID_MINING_CURSOR"
            return false
        end
        if not persistMiningCursor(completedCursor) then return false end
        stats:add("floors_completed", 1)
    end

    for floor = config.mining.floorCount, 1, -1 do
        local route = checkpoint:floorLanding(floor)
        if not route then
            persistenceError = "LANDING_NOT_RECORDED"
            return false
        end
        local returned, outcome = StairRoute.returnToSurface({
            pose = pos,
            route = route,
            move = checkedMoveForRoute,
            turn = checkedTurnForRoute,
        })
        if outcome.ok ~= true then
            persistenceError = outcome.code or "STAIR_RETURN_FAILED"
            print("ERROR: " .. tostring(persistenceError))
            return false
        end
        if pos.x ~= returned.x or pos.y ~= returned.y
            or pos.z ~= returned.z or pos.facing ~= returned.facing then
            persistenceError = "POSITION_ERROR"
            return false
        end
    end

    if pos.x ~= 0 or pos.y ~= 0 or pos.z ~= 0 or pos.facing ~= 0 then
        persistenceError = "POSITION_ERROR"
        return false
    end

    print("=== Mining Complete: returned to surface origin ===")
    print(string.format("Final position: x=%d, y=%d, z=%d", pos.x, pos.y, pos.z))
    local summary = Statistics.jobSummary(stats, {
        startedAt = startedAt,
        endedAt = os.epoch("utc") / 1000,
    })
    for _, line in ipairs(Statistics.formatJobSummary(summary)) do print(line) end
    return true
end

-- ============================================================================
-- MAIN
-- ============================================================================

local function main(...)

    local args = { ... }
    if args[1] == "status" then
        if type(fsApi) ~= "table" or type(textutilsApi) ~= "table"
            or type(fsApi.combine) ~= "function" or type(fsApi.exists) ~= "function" then
            print("Recovery status unavailable: persistence API missing")
            return
        end
        statePath = fsApi.combine("oreMiner", "state.json")
        local session, code = Checkpoint.load(statePath, configSnapshot(), fsApi, textutilsApi)
        local state = session and session:snapshotState() or nil
        local occupied = 0
        if type(turtle.getItemCount) == "function" then
            for slot = 1, 16 do
                if turtle.getItemCount(slot) > 0 then occupied = occupied + 1 end
            end
        end
        local fuel = type(turtle.getFuelLevel) == "function" and turtle.getFuelLevel() or "unavailable"
        RecoveryStatus.display(state, code, fuel, occupied,
            config.inventory.returnThreshold, terminalPrint)
        return
    elseif args[1] == "resume" then
        if type(fsApi) ~= "table" or type(textutilsApi) ~= "table"
            or type(fsApi.combine) ~= "function" then
            print("Resume unavailable: persistence API missing")
            return
        end
        statePath = fsApi.combine("oreMiner", "state.json")
        local saved, loadCode = Checkpoint.load(statePath, configSnapshot(), fsApi, textutilsApi)
        local resumable, reason = Recovery.classify(saved and saved:snapshotState() or nil, loadCode)
        if not resumable then
            print("Resume stopped safely: " .. tostring(reason or loadCode))
            return
        end
        local snapshot = saved:snapshotState()
        if snapshot.progress.phase == "main_side_start"
            or snapshot.progress.phase == "main_side_return"
            or snapshot.progress.phase == "main_shaft" or snapshot.progress.phase == "junction"
            or snapshot.progress.phase == "branch_outbound_lower"
            or snapshot.progress.phase == "branch_turnaround"
            or snapshot.progress.phase == "branch_upper_return"
            or snapshot.progress.phase == "branch_return_to_junction" then
            local MainShaftResume = require("src.mining.main_shaft_resume")
            local start, startCode
            if snapshot.progress.phase == "main_side_start"
                or snapshot.progress.phase == "main_side_return" then
                start = { mainSide = snapshot.progress.mainSide or "right" }
            elseif snapshot.progress.phase == "main_shaft" then
                start, startCode = MainShaftResume.start(
                    snapshot.progress, config.num_branches, config.spacing)
            elseif snapshot.progress.phase == "junction" then
                local JunctionResume = require("src.mining.junction_resume")
                start, startCode = JunctionResume.start(
                    snapshot.progress, config.num_branches, config.spacing)
            else
                local BranchResume = require("src.mining.branch_resume")
                start, startCode = BranchResume.start(snapshot.progress,
                    config.num_branches, config.spacing, config.branch_length)
            end
            if snapshot.progress.floor > config.mining.floorCount or not start then
                print("Resume stopped safely: " .. tostring(startCode or "MAIN_SHAFT_CURSOR_OUT_OF_RANGE"))
                return
            end
        end
        local target = snapshot.resumeCheckpoint.pose
        if snapshot.progress.phase == "main_side_return" and not snapshot.service then
            -- The return cursor spans already recorded main-shaft edges.
            -- Continue from the last committed cell, including a service trip.
            target = snapshot.pose
        end
        if snapshot.progress.phase == "stairs"
            and snapshot.progress.nextAction == "cross_landing" then
            -- This cursor covers the complete crossing/descent unit. Recovery
            -- classifier validated both endpoints; continue at committed pose.
            target = snapshot.pose
        end
        local current = snapshot.pose
        local path, pathCode = RouteHome.path(snapshot.route, current, nil, target)
        if not path then
            print("Resume stopped safely: " .. tostring(pathCode))
            return
        end
        local origin = { x = 0, y = 0, z = 0, facing = 0 }
        local homePath, homePathCode = RouteHome.path(snapshot.route, current, nil, origin)
        if not homePath then
            print("Resume stopped safely: " .. tostring(homePathCode))
            return
        end
        local resumeMoves = #path
        if snapshot.progress.phase == "floor_complete" then
            local routes = saved:floorLandings()
            for floor = 1, snapshot.progress.floor do
                local route = routes[floor]
                if not route then
                    print("Resume stopped safely: LANDING_NOT_RECORDED")
                    return
                end
                resumeMoves = resumeMoves + route.entryMoves + (2 * route.steps) + 1
            end
            local landing = saved:floorLanding(snapshot.progress.floor)
            local landingToTarget, landingPathCode = RouteHome.path(
                snapshot.route, landing.landing, nil, target)
            if not landingToTarget then
                print("Resume stopped safely: " .. tostring(landingPathCode))
                return
            end
            resumeMoves = resumeMoves + #landingToTarget
        elseif snapshot.progress.phase == "surface_entry" then
            -- This cursor is admitted only at surface origin; the next floor
            -- executor owns the four-block entry and first stair descent.
            resumeMoves = 0
        elseif snapshot.progress.phase == "stairs"
            and snapshot.progress.nextAction == "cross_landing" then
            -- Budget the saved clear landing crossing plus the new recorded
            -- stair route before resuming from the preceding landing.
            local route = saved:floorLanding(snapshot.progress.floor)
            if not route or route.steps < 1
                or route.entryMoves ~= 1
                or route.steps ~= config.mining.stairStepsPerFloor then
                print("Resume stopped safely: LANDING_ROUTE_INVALID")
                return
            end
            resumeMoves = 1
        end
        if snapshot.service then
            local targetHomePath, targetHomeCode = RouteHome.path(
                snapshot.route, target, nil, origin)
            if not targetHomePath then
                print("Resume stopped safely: " .. tostring(targetHomeCode))
                return
            end
            -- Service replays base -> checkpoint after resupply; its resupply
            -- admission also guarantees a checkpoint -> base return.
            resumeMoves = 2 * #targetHomePath
        end
        pos = snapshot.pose
        knownRoute = snapshot.route
        checkpoint = saved
        if snapshot.progress.phase == "surface_entry" and not snapshot.service then
            local suppliesReady, supplyCode
            repeat
                suppliesReady, supplyCode = prepareStartupSupplies()
                if not suppliesReady and (supplyCode == "NO_FUEL_SUPPLY"
                    or supplyCode == "NO_TORCHES") then
                    print("Supply is short. Waiting at base; restock the left chest to resume.")
                    sleep(5)
                    if type(minerExitRequested) == "function" and minerExitRequested() then
                        error("EXIT_REQUESTED", 0)
                    end
                end
            until suppliesReady or (supplyCode ~= "NO_FUEL_SUPPLY"
                and supplyCode ~= "NO_TORCHES")
            if not suppliesReady then
                print("Resume stopped safely: " .. tostring(supplyCode))
                return
            end
        end
        local fuelTarget, fuelCode = ResumeCommitment.targetFuelForTrips(
            #homePath, resumeMoves, config.fuel_reserve, 1)
        if not fuelTarget or not refuel(fuelTarget) then
            print("Resume stopped safely: " .. tostring(fuelCode or "NO_FUEL"))
            return
        end
        local miningStatusSaved, miningStatusCode = saved:markMining(
            snapshot.pose, snapshot.route, configSnapshot())
        if not miningStatusSaved then
            print("Resume stopped safely: " .. tostring(miningStatusCode or "STATE_WRITE_FAILED"))
            return
        end
        pos = snapshot.pose
        knownRoute = snapshot.route
        checkpoint = saved
        stats = Statistics.new(saved:statistics())
        statisticsStartedAt = os.epoch("utc") / 1000
        checkpoint:setStatisticsProvider(function()
            local values = stats:snapshot()
            values.active_runtime_seconds = stats:get("active_runtime_seconds")
                + math.max(0, os.epoch("utc") / 1000 - statisticsStartedAt)
            return values
        end)
        activeFloor = snapshot.progress.floor
        local travelTarget = target
        if snapshot.vein then
            local vein = snapshot.vein
            local unwind = VeinTraversal.unwindSaved(vein, {
                pose = function() return pos end,
                turn = function(direction) return turn(direction) end,
                move = function(direction)
                    deferVeinMovementCommit = true
                    local moved = move(direction)
                    deferVeinMovementCommit = false
                    return moved == true
                end,
            }, function(veinState)
                local savedVein, saveCode = checkpoint:commitVeinAction(
                    pos, knownRoute, configSnapshot(), veinState)
                if not savedVein then persistenceError = saveCode end
                return savedVein
            end)
            if not unwind.ok then
                print("Resume stopped safely: " .. tostring(unwind.code))
                return
            end
            target = vein.checkpoint
            travelTarget = target
        end
        if snapshot.progress.phase == "floor_complete" then
            travelTarget = { x = 0, y = 0, z = 0, facing = 0 }
        end
        if snapshot.service then
            local serviced, serviceCode
            repeat
                serviced, serviceCode = inventoryService.resume(target)
                if not serviced and (serviceCode == "NO_TORCHES"
                    or serviceCode == "NO_FUEL_SUPPLY") then
                    print("Supply is short. Waiting at base; restock the left chest to resume.")
                    sleep(5)
                    if type(minerExitRequested) == "function" and minerExitRequested() then
                        error("EXIT_REQUESTED", 0)
                    end
                end
            until serviced or (serviceCode ~= "NO_TORCHES"
                and serviceCode ~= "NO_FUEL_SUPPLY")
            if not serviced then
                -- Service-stage failures (for example a chest that was fixed
                -- after the last attempt) retain a known pose and checkpoint.
                -- Keep that snapshot retryable; unsafe actions and mining
                -- failures remain terminal through their existing paths.
                if serviceCode ~= "NO_SUPPLY_CHEST" and serviceCode ~= "NO_OUTPUT_CHEST"
                    and serviceCode ~= "NO_BULK_CHEST" and serviceCode ~= "CHEST_FULL"
                    and serviceCode ~= "UNLOAD_FAILED" then
                    markFatal(serviceCode or "SERVICE_RESUME_FAILED")
                end
                print("Resume stopped safely: " .. tostring(serviceCode))
                return
            end
        else
            local arrived, outcome = RouteHome.run({
                pose = pos,
                route = knownRoute,
                targetPose = travelTarget,
                homeFacing = travelTarget.facing,
                move = checkedMoveForRoute,
                turn = checkedTurnForRoute,
            })
            if outcome.ok ~= true then
                print("Resume stopped safely: " .. tostring(outcome.code))
                return
            end
            pos = arrived
        end
        if snapshot.progress.phase == "floor_complete" and not snapshot.service then
            local landing = checkpoint:floorLanding(snapshot.progress.floor)
            if not landing then
                print("Resume stopped safely: LANDING_NOT_RECORDED")
                return
            end
            local routes = checkpoint:floorLandings()
            local resumed, stairOutcome = StairRoute.resumeToLanding({
                pose = pos, floor = snapshot.progress.floor, routes = routes,
                move = checkedMoveForRoute,
            })
            if stairOutcome.ok ~= true then
                print("Resume stopped safely: " .. tostring(stairOutcome.code))
                return
            end
            pos = resumed
            local reached, routeOutcome = RouteHome.run({
                pose = pos, route = knownRoute, targetPose = target,
                homeFacing = target.facing, move = checkedMoveForRoute,
                turn = checkedTurnForRoute,
            })
            if routeOutcome.ok ~= true then
                print("Resume stopped safely: " .. tostring(routeOutcome.code))
                return
            end
            pos = reached
        end
        local savedPose = target
        if pos.x ~= savedPose.x or pos.y ~= savedPose.y or pos.z ~= savedPose.z
            or pos.facing ~= savedPose.facing then
            print("Resume stopped safely: RESUME_POSE_MISMATCH")
            return
        end
        if snapshot.progress.phase == "floor_complete" then
            local resumed = executeFloors(snapshot.progress.floor + 1)
            if not resumed then
                markFatal(persistenceError or "RESUME_MINING_STOPPED")
                print("Resume stopped safely: " .. tostring(persistenceError or "RESUME_MINING_STOPPED"))
                return
            end
            local completed, completeCode = checkpoint:markComplete(
                pos, knownRoute, configSnapshot())
            if not completed then
                print("Resume stopped safely: " .. tostring(completeCode or "STATE_WRITE_FAILED"))
                return
            end
            print("Resume completed the remaining floors and returned to surface origin.")
            return
        end
        if snapshot.progress.phase == "main_side_start"
            or snapshot.progress.phase == "main_side_return"
            or snapshot.progress.phase == "main_shaft" or snapshot.progress.phase == "junction"
            or snapshot.progress.phase == "branch_outbound_lower"
            or snapshot.progress.phase == "branch_turnaround"
            or snapshot.progress.phase == "branch_upper_return"
            or snapshot.progress.phase == "branch_return_to_junction" then
            local resumed = executeFloors(snapshot.progress.floor, snapshot.progress)
            if not resumed then
                markFatal(persistenceError or "RESUME_MINING_STOPPED")
                print("Resume stopped safely: " .. tostring(persistenceError or "RESUME_MINING_STOPPED"))
                return
            end
            local completed, completeCode = checkpoint:markComplete(
                pos, knownRoute, configSnapshot())
            if not completed then
                print("Resume stopped safely: " .. tostring(completeCode or "STATE_WRITE_FAILED"))
                return
            end
            print("Resume completed the remaining floors and returned to surface origin.")
            return
        end
        if snapshot.progress.phase == "surface_entry" then
            local resumed = executeFloors(snapshot.progress.floor)
            if not resumed then
                markFatal(persistenceError or "RESUME_MINING_STOPPED")
                print("Resume stopped safely: " .. tostring(persistenceError or "RESUME_MINING_STOPPED"))
                return
            end
            local completed, completeCode = checkpoint:markComplete(
                pos, knownRoute, configSnapshot())
            if not completed then
                print("Resume stopped safely: " .. tostring(completeCode or "STATE_WRITE_FAILED"))
                return
            end
            print("Resume completed the remaining floors and returned to surface origin.")
            return
        end
        if snapshot.progress.phase == "stairs"
            and snapshot.progress.nextAction == "cross_landing" then
            local resumed = executeFloors(snapshot.progress.floor)
            if not resumed then
                markFatal(persistenceError or "RESUME_MINING_STOPPED")
                print("Resume stopped safely: " .. tostring(persistenceError or "RESUME_MINING_STOPPED"))
                return
            end
            local completed, completeCode = checkpoint:markComplete(
                pos, knownRoute, configSnapshot())
            if not completed then
                print("Resume stopped safely: " .. tostring(completeCode or "STATE_WRITE_FAILED"))
                return
            end
            print("Resume completed the remaining floors and returned to surface origin.")
            return
        end
        print("Resume restored the committed checkpoint; active cursor restart is not supported yet")
        return
    elseif args[1] == "home" then
        if type(fsApi) ~= "table" or type(textutilsApi) ~= "table"
            or type(fsApi.combine) ~= "function" then
            print("Home unavailable: persistence API missing")
            return
        end
        statePath = fsApi.combine("oreMiner", "state.json")
        local saved, loadCode = Checkpoint.load(statePath, configSnapshot(), fsApi, textutilsApi)
        local snapshot = saved and saved:snapshotState() or nil
        if type(snapshot) ~= "table" or snapshot.poseCertainty ~= "known"
            or snapshot.pendingAction ~= nil then
            print("Home stopped safely: " .. tostring(loadCode == "STATE_LOADED"
                and "POSITION_UNCERTAIN" or loadCode or "RESUME_STATE_UNSAFE"))
            return
        end
        local origin = { x = 0, y = 0, z = 0, facing = 0 }
        if snapshot.status == "complete" and snapshot.pose.x == origin.x
            and snapshot.pose.y == origin.y and snapshot.pose.z == origin.z then
            print("Already home; the saved job is complete.")
            return
        end
        pos = snapshot.pose
        knownRoute = snapshot.route
        checkpoint = saved
        activeFloor = snapshot.progress and snapshot.progress.floor or nil
        local paused, pauseCode = checkpoint:markPaused(pos, knownRoute, configSnapshot())
        if not paused then
            print("Home stopped safely: " .. tostring(pauseCode or "STATE_WRITE_FAILED"))
            return
        end
        if snapshot.vein then
            local unwind = VeinTraversal.unwindSaved(snapshot.vein, {
                pose = function() return pos end,
                turn = function(direction) return turn(direction) end,
                move = function(direction)
                    deferVeinMovementCommit = true
                    local moved = move(direction)
                    deferVeinMovementCommit = false
                    return moved == true
                end,
            }, function(veinState)
                local savedVein, saveCode = checkpoint:commitVeinAction(
                    pos, knownRoute, configSnapshot(), veinState)
                if not savedVein then persistenceError = saveCode end
                return savedVein
            end)
            if not unwind.ok then
                print("Home stopped safely: " .. tostring(unwind.code))
                return
            end
        end
        if not snapshot.service then
            local homePath, pathCode = RouteHome.path(knownRoute, pos, nil, origin)
            if not homePath then
                print("Home stopped safely: " .. tostring(pathCode))
                return
            end
        end
        local serviceSaved, serviceCode = checkpoint:setService({
            stage = "returning", checkpoint = origin,
            resumeProgress = snapshot.progress,
        }, pos, knownRoute, configSnapshot())
        if not serviceSaved then
            print("Home stopped safely: " .. tostring(serviceCode or "STATE_WRITE_FAILED"))
            return
        end
        local reached, returnCode = travelRecordedRoute(origin)
        if not reached then
            print("Home stopped safely: " .. tostring(returnCode or "RETURN_FAILED"))
            return
        end
        local parked, parkedCode = checkpoint:setService({
            stage = "at_base", checkpoint = origin,
            resumeProgress = snapshot.progress,
        }, pos, knownRoute, configSnapshot())
        if not parked then
            print("Home reached, but pause state could not be saved: " .. tostring(parkedCode))
            return
        end
        print("Home reached. Run `miner resume` to continue the saved job.")
        return
    end

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
    local startup = Startup.newRunDecision(existing, stateCode)
    if not startup.start then
        print(startup.message)
        return
    elseif confirmConfiguration() then
        if not newRun() then error("STATE_WRITE_FAILED: unable to create initial snapshot") end
        local suppliesReady, supplyCode
        repeat
            suppliesReady, supplyCode = prepareStartupSupplies()
            if not suppliesReady and (supplyCode == "NO_FUEL_SUPPLY" or supplyCode == "NO_TORCHES") then
                print("Supply is short. Waiting at base; restock the left chest to start.")
                sleep(5)
                if type(minerExitRequested) == "function" and minerExitRequested() then
                    error("EXIT_REQUESTED", 0)
                end
            end
        until suppliesReady or (supplyCode ~= "NO_FUEL_SUPPLY" and supplyCode ~= "NO_TORCHES")
        local ok
        if suppliesReady and hasStartupFuel() then
            ok = executeFloors()
        else
            persistenceError = supplyCode or "NO_FUEL"
            print("Stopping before movement: " .. tostring(persistenceError))
            ok = false
        end
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

main(...)
