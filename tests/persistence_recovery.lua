local Recovery = require("src.persistence.recovery")
local Cursor = require("src.mining.cursor")
local Checkpoint = require("src.persistence.checkpoint")
local State = require("src.persistence.state")
local InventoryService = require("src.inventory.service")
local VeinTraversal = require("src.mining.vein_traversal")

-- Model a process restart after each durable coordinator boundary: write the
-- checkpoint, discard the live session, reload the serialized snapshot, then
-- require recovery classification to either admit its exact cursor or stop.
local disk = {}
local fs = {
    exists = function(path) return disk[path] ~= nil end,
    open = function(path, mode)
        if mode == "r" then
            if disk[path] == nil then return nil end
            local content = disk[path]
            return { readAll = function() return content end, close = function() end }
        end
        local buffer = ""
        return {
            write = function(value) buffer = buffer .. value end,
            close = function() disk[path] = buffer end,
        }
    end,
    delete = function(path) disk[path] = nil end,
    move = function(fromPath, toPath)
        assert(disk[fromPath] ~= nil)
        disk[toPath], disk[fromPath] = disk[fromPath], nil
    end,
}
local function serialize(value)
    local function encode(item)
        if type(item) == "string" then return string.format("%q", item) end
        if type(item) == "number" or type(item) == "boolean" then return tostring(item) end
        if item == nil then return "nil" end
        local entries = {}
        for key, child in pairs(item) do
            local rendered = type(key) == "string"
                and "[" .. string.format("%q", key) .. "]" or "[" .. tostring(key) .. "]"
            entries[#entries + 1] = rendered .. "=" .. encode(child)
        end
        return "{" .. table.concat(entries, ",") .. "}"
    end
    return encode(value)
end
local textutils = {
    serialize = serialize,
    unserialize = function(raw) return load("return " .. raw)() end,
}
local crashConfig = {
    branch_length = 30, num_branches = 20, spacing = 3,
    stair_steps_per_floor = 8,
    pave = false, vein_mine = true,
}
local origin = { x = 0, y = 0, z = 0, facing = 0 }
local mainCursor = assert(Cursor.mainShaft(1, 1, 0, 1))
local mainPose = { x = 0, y = -8, z = -13, facing = 1 }
local landingPose = { x = 0, y = -8, z = -13, facing = 0 }
local mainRoute = { home = "0,0,0", edges = {} }
local function connect(from, to)
    mainRoute.edges[from] = mainRoute.edges[from] or {}
    mainRoute.edges[to] = mainRoute.edges[to] or {}
    mainRoute.edges[from][to], mainRoute.edges[to][from] = true, true
end
local previous = "0,0,0"
for step = 1, 4 do
    local nextKey = "0,0,-" .. step
    connect(previous, nextKey)
    previous = nextKey
end
for step = 1, 8 do
    local forwardKey = "0," .. (-(step - 1)) .. ",-" .. (4 + step)
    local downKey = "0,-" .. step .. ",-" .. (4 + step)
    connect(previous, forwardKey)
    connect(forwardKey, downKey)
    previous = downKey
end
local landingKey = "0,-8,-13"
connect(previous, landingKey)
connect("0,-8,-13", "1,-8,-13")
connect("1,-8,-13", "2,-8,-13")
connect("2,-8,-13", "3,-8,-13")
local function crashAfter(label, writeBoundary, expectedSafe)
    local path = "crash-" .. label .. ".json"
    disk = {}
    local session = assert(Checkpoint.create(crashConfig, mainPose, mainRoute,
        "crash-" .. label, path, fs, textutils))
    assert(session:setProgress(mainCursor, mainPose, mainRoute, crashConfig),
        "initial cursor must be durable at " .. label)
    assert(session:recordFloorLanding({ floor = 1, origin = origin,
        mouth = { x = 0, y = 0, z = -4, facing = 0 },
        rear = { x = 0, y = -8, z = -12, facing = 0 },
        landing = landingPose, steps = 8, entryMoves = 4 }, mainPose, mainRoute, crashConfig),
        "landing must be durable for main-shaft recovery at " .. label)
    assert(writeBoundary(session), "crash boundary must persist: " .. label)
    session = nil -- discard all in-memory coordinator state
    local snapshot, loadCode = State.load(path, crashConfig, fs, textutils)
    assert(snapshot, "crash boundary snapshot must reload: " .. label .. " " .. tostring(loadCode))
    if expectedSafe == "complete" then
        assert(snapshot.status == "complete", "completion boundary must reload as complete")
    elseif expectedSafe == "fatal" then
        assert(snapshot.status == "error" and snapshot.error == "INJECTED_FAILURE",
            "fatal boundary must reload its terminal error code")
    else
        local resumable, recoveryCode = Recovery.classify(snapshot, loadCode)
        assert(resumable == expectedSafe,
            "unexpected recovery decision after " .. label .. ": " .. tostring(recoveryCode))
    end
end

-- Inject a process restart at every cursor family emitted before a bounded
-- coordinator unit. Each case writes through Checkpoint, reloads serialized
-- bytes, then classifies the recovered snapshot (including intentional stops).
local landingRecord = {
    floor = 1, origin = origin,
    mouth = { x = 0, y = 0, z = -4, facing = 0 },
    rear = { x = 0, y = -8, z = -12, facing = 0 },
    landing = landingPose, steps = 8, entryMoves = 4,
}
-- A supply shortage during interrupted service stays recoverable across a
-- process restart so `miner resume` can wait for later chest restocking.
disk = {}
local supplyWaitPath = "crash-supply-wait.json"
local supplyWaitCursor = assert(Cursor.mainShaft(1, 1, 0, 1))
local supplyWaitSession = assert(Checkpoint.create(crashConfig, mainPose, mainRoute,
    "crash-supply-wait", supplyWaitPath, fs, textutils))
assert(supplyWaitSession:setProgress(supplyWaitCursor, mainPose, mainRoute, crashConfig))
assert(supplyWaitSession:recordFloorLanding(landingRecord, mainPose, mainRoute, crashConfig))
assert(supplyWaitSession:setService({ stage = "at_base", checkpoint = origin,
    resumeProgress = supplyWaitCursor }, origin, mainRoute, crashConfig))
assert(supplyWaitSession:markFatal("NO_TORCHES", origin, mainRoute, crashConfig))
supplyWaitSession = nil
local supplyWaitSnapshot, supplyWaitCode = State.load(supplyWaitPath, crashConfig, fs, textutils)
local supplyWaitAllowed, supplyWaitReason = Recovery.classify(supplyWaitSnapshot, supplyWaitCode)
assert(supplyWaitSnapshot and supplyWaitAllowed,
    "known-pose supply-short service state must remain resumable after reboot: "
        .. tostring(supplyWaitReason))

local cursorCrashCases = {
    { "surface-entry", assert(Cursor.stairs(1, 0, "enter_surface")), origin, true },
    { "main-shaft", mainCursor, mainPose, true },
}
-- A slice is an indivisible logical work unit today. Reload every persisted
-- pre-slice cursor and require a specific refusal: committed movement/dig
-- breadcrumbs do not identify which lateral/vertical sweep operation ran.
for stairStep = 1, 8 do
    cursorCrashCases[#cursorCrashCases + 1] = {
        "stair-slice-stop-" .. stairStep,
        assert(Cursor.stairs(1, stairStep, "descend_stair_slice")),
        mainPose, false, "STAIR_SLICE_RESUME_UNSUPPORTED",
    }
end
cursorCrashCases[#cursorCrashCases + 1] = {
    "landing-carve-stop",
    assert(Cursor.stairs(1, 8, "prepare_landing")),
    mainPose, false, "LANDING_CARVE_RESUME_UNSUPPORTED",
}
for _, case in ipairs(cursorCrashCases) do
    local label, cursor, pose, expectedSafe, expectedCode = case[1], case[2], case[3], case[4], case[5]
    local path = "crash-cursor-" .. label .. ".json"
    disk = {}
    local route = { home = "0,0,0", edges = {} }
    local previousKey = "0,0,0"
    route.edges[previousKey] = {}
    local distance = math.abs(pose.x) + math.abs(pose.y) + math.abs(pose.z)
    for step = 1, distance do
        local key
        if step <= math.abs(pose.x) then
            key = (pose.x < 0 and -step or step) .. ",0,0"
        elseif step <= math.abs(pose.x) + math.abs(pose.y) then
            key = pose.x .. "," .. (pose.y < 0 and -(step - math.abs(pose.x))
                or (step - math.abs(pose.x))) .. ",0"
        else
            local zStep = step - math.abs(pose.x) - math.abs(pose.y)
            key = pose.x .. "," .. pose.y .. "," .. (pose.z < 0 and -zStep or zStep)
        end
        route.edges[previousKey][key] = true
        route.edges[key] = route.edges[key] or {}
        route.edges[key][previousKey] = true
        previousKey = key
    end
    local session = assert(Checkpoint.create(crashConfig, pose, route,
        "crash-cursor-" .. label, path, fs, textutils))
    assert(session:setProgress(cursor, pose, route, crashConfig),
        "cursor boundary must persist: " .. label)
    if cursor.phase == "main_shaft" then
        route = mainRoute
        session = assert(Checkpoint.create(crashConfig, pose, route,
            "crash-cursor-" .. label, path, fs, textutils))
        assert(session:setProgress(cursor, pose, route, crashConfig),
            "cursor boundary must persist on the active route: " .. label)
        assert(session:recordFloorLanding(landingRecord, pose, route, crashConfig),
            "floor landing must persist before cursor crash: " .. label)
    end
    session = nil
    local recovered, loadCode = State.load(path, crashConfig, fs, textutils)
    assert(recovered, "cursor crash snapshot must reload: " .. label .. " " .. tostring(loadCode))
    local resumed, recoveryCode = Recovery.classify(recovered, loadCode)
    assert(resumed == expectedSafe,
        "unexpected recovery admission after " .. label .. ": " .. tostring(recoveryCode))
    if expectedCode then
        assert(recoveryCode == expectedCode,
            "unsupported cursor should retain its precise stop reason: " .. label)
    else
        assert(recoveryCode == "RESUME_SAFE_CHECKPOINT",
            "supported cursor should use the normal recovery admission: " .. label)
    end
end

crashAfter("cursor", function(session)
    return session:setProgress(mainCursor, mainPose, mainRoute, crashConfig)
end, true)
crashAfter("return-start", function(session)
    return session:setService({ stage = "returning", checkpoint = origin,
        resumeProgress = mainCursor }, mainPose, mainRoute, crashConfig)
end, true)
crashAfter("home-arrival", function(session)
    return session:setService({ stage = "at_base", checkpoint = origin,
        resumeProgress = mainCursor }, origin, mainRoute, crashConfig)
end, true)
crashAfter("unload-start", function(session)
    return session:setService({ stage = "unloading", checkpoint = origin,
        resumeProgress = mainCursor }, origin, mainRoute, crashConfig)
end, true)
crashAfter("unload-complete", function(session)
    return session:setService({ stage = "resuming", checkpoint = origin,
        resumeProgress = mainCursor }, origin, mainRoute, crashConfig)
end, true)
crashAfter("resume-departure", function(session)
    return session:setService({ stage = "resuming", checkpoint = mainPose,
        resumeProgress = mainCursor }, mainPose, mainRoute, crashConfig)
end, true)
crashAfter("stair-climb-checkpoint", function(session)
    -- Climb is a bounded logical slice: only its committed centreline endpoint
    -- is restartable; a physical move in flight remains pending/uncertain.
    return session:setProgress(mainCursor, mainPose, mainRoute, crashConfig)
end, true)
crashAfter("vein-unwind-checkpoint", function(session)
    local intermediate = { x = 0, y = -8, z = -14, facing = 0 }
    connect("0,-8,-13", "0,-8,-14")
    local cursor = assert(Cursor.mainShaft(1, 1, 0, 1))
    local checkpointPose = { x = 0, y = -8, z = -13, facing = 0 }
    local entryPose = { x = 0, y = -8, z = -14, facing = 0 }
    local active = {
        stage = "active", checkpoint = checkpointPose,
        visited = { ["0,-8,-14"] = true },
        frontier = { { next = 1, rotateOnReturn = false } },
        route = { { inverse = "back", facing = 0 } }, blocks = 1,
    }
    local saved = session:setProgress(cursor, checkpointPose, mainRoute, crashConfig)
    if not saved then return false end
    saved = session:commitVeinAction(entryPose, mainRoute, crashConfig, active)
    if not saved then return false end
    local record = {
        stage = "unwinding", checkpoint = checkpointPose,
        visited = { ["0,-8,-14"] = true },
        frontier = { { next = 1, rotateOnReturn = false } },
        route = { { inverse = "back", facing = 0 } }, blocks = 1,
    }
    saved = session:setVein(record, intermediate, mainRoute, crashConfig)
    if not saved then return false end
    return session:setProgress(cursor, intermediate, mainRoute, crashConfig)
end, false)
crashAfter("resume-travel-checkpoint", function(session)
    return session:setService({ stage = "resuming", checkpoint = mainPose,
        resumeProgress = mainCursor }, origin, mainRoute, crashConfig)
end, true)

-- A process restart after each committed edge on service replay must reload
-- the intermediate pose and continue from that point without repeating it.
do
    local path = "crash-resume-travel-edges.json"
    disk = {}
    local session = assert(Checkpoint.create(crashConfig, origin, mainRoute,
        "crash-resume-travel-edges", path, fs, textutils))
    assert(session:setProgress(mainCursor, mainPose, mainRoute, crashConfig))
    assert(session:recordFloorLanding(landingRecord, mainPose, mainRoute, crashConfig))
    assert(session:setService({ stage = "resuming", checkpoint = mainPose,
        resumeProgress = mainCursor }, origin, mainRoute, crashConfig))
    local physicalPose = { x = origin.x, y = origin.y, z = origin.z, facing = origin.facing }
    local pathHome = { "0,0,0", "0,0,-1", "0,0,-2", "0,0,-3", "0,0,-4" }
    local pathTarget = { "0,0,-4", "0,-1,-5", "0,-1,-6", "0,-2,-7", mainPose.x .. "," .. mainPose.y .. "," .. mainPose.z }
    local function applyKey(key)
        local x, y, z = key:match("^(-?%d+),(-?%d+),(-?%d+)$")
        physicalPose.x, physicalPose.y, physicalPose.z = tonumber(x), tonumber(y), tonumber(z)
    end
    local function walk(keys, startAt, destination)
        for index = startAt, #keys do
            local key = keys[index]
            local from = table.concat({ physicalPose.x, physicalPose.y, physicalPose.z }, ",")
            local fromEdges = mainRoute.edges[from]
            assert(fromEdges and fromEdges[key], "resume travel may use only recorded route edges")
            applyKey(key)
            local saved, saveCode = session:save(physicalPose, mainRoute, crashConfig)
            assert(saved, "each movement commit persists before a possible restart: " .. tostring(saveCode))
            session = nil
            local reloaded, loadCode = State.load(path, crashConfig, fs, textutils)
            assert(reloaded and reloaded.pose.x == physicalPose.x
                and reloaded.pose.y == physicalPose.y and reloaded.pose.z == physicalPose.z,
                "restart restores the committed service travel pose: " .. tostring(loadCode))
            local admitted, recoveryCode = Recovery.classify(reloaded, loadCode)
            assert(admitted and recoveryCode == "RESUME_SAFE_SERVICE",
                "committed service travel edge remains recoverable: " .. tostring(recoveryCode))
            session = assert(Checkpoint.load(path, crashConfig, fs, textutils))
            if destination and index == #keys then
                assert(physicalPose.x == destination.x and physicalPose.y == destination.y
                    and physicalPose.z == destination.z,
                    "replay must reach the requested checkpoint")
            end
        end
    end
    -- Four entry edges reach the recorded mouth; the remaining path represents
    -- recorded stair edges toward a saved mining checkpoint.
    walk(pathHome, 2)
    -- Build a recorded stair route from the mouth to the checkpoint so every
    -- replay edge is checked against durable adjacency evidence.
    local previousKey = "0,0,-4"
    for step = 1, 8 do
        local forwardKey = "0," .. (-(step - 1)) .. ",-" .. (4 + step)
        local downKey = "0,-" .. step .. ",-" .. (4 + step)
        connect(previousKey, forwardKey)
        connect(forwardKey, downKey)
        previousKey = downKey
    end
    connect(previousKey, "0,-8,-13")
    pathTarget = { "0,0,-4" }
    for step = 1, 8 do
        pathTarget[#pathTarget + 1] = "0," .. (-(step - 1)) .. ",-" .. (4 + step)
        pathTarget[#pathTarget + 1] = "0,-" .. step .. ",-" .. (4 + step)
    end
    pathTarget[#pathTarget + 1] = "0,-8,-13"
    walk(pathTarget, 2, mainPose)
    assert(physicalPose.x == mainPose.x and physicalPose.y == mainPose.y
        and physicalPose.z == mainPose.z,
        "resumed travel must finish at the original mining checkpoint")
end

crashAfter("run-complete", function(session)
    return session:markComplete(origin, mainRoute, crashConfig)
end, "complete")
crashAfter("fatal", function(session)
    return session:markFatal("INJECTED_FAILURE", mainPose, mainRoute, crashConfig)
end, "fatal")

-- Restart from a real serialized service boundary, then run the same service
-- replay executor used by the coordinator. This joins snapshot recovery
-- admission to the exact home -> resupply -> checkpoint route behavior.
local servicePath = "crash-interrupted-service.json"
disk = {}
local serviceSession = assert(Checkpoint.create(crashConfig, mainPose, mainRoute,
    "crash-interrupted-service", servicePath, fs, textutils))
assert(serviceSession:setProgress(mainCursor, mainPose, mainRoute, crashConfig))
assert(serviceSession:recordFloorLanding({ floor = 1, origin = origin,
    mouth = { x = 0, y = 0, z = -4, facing = 0 },
    rear = { x = 0, y = -8, z = -12, facing = 0 },
    landing = landingPose, steps = 8, entryMoves = 4 }, mainPose, mainRoute, crashConfig))
assert(serviceSession:setService({ stage = "unloading", checkpoint = origin,
    resumeProgress = mainCursor }, origin, mainRoute, crashConfig))
serviceSession = nil
local interrupted, interruptedCode = Checkpoint.load(servicePath, crashConfig, fs, textutils)
assert(interrupted, "interrupted service snapshot must reload: " .. tostring(interruptedCode))
local interruptedState = interrupted:snapshotState()
local serviceAllowed, serviceRecoveryCode = Recovery.classify(interruptedState, interruptedCode)
assert(serviceAllowed and serviceRecoveryCode == "RESUME_SAFE_SERVICE",
    "the reloaded interrupted service must pass the same admission gate as resume")
-- A recoverable chest lookup error at base keeps the committed service stage.
-- Once the operator fixes the layout, resume must reach the service executor
-- and repeat its current chest checks instead of rejecting the error status.
assert(interrupted:markFatal("NO_SUPPLY_CHEST", origin, mainRoute, crashConfig))
interrupted = nil
local fixedService, fixedServiceCode = Checkpoint.load(servicePath, crashConfig, fs, textutils)
assert(fixedService, "known-pose service error snapshot must reload: " .. tostring(fixedServiceCode))
local fixedServiceAllowed, fixedServiceReason = Recovery.classify(
    fixedService:snapshotState(), fixedServiceCode)
assert(fixedServiceAllowed and fixedServiceReason == "RESUME_SAFE_SERVICE",
    "known-pose NO_SUPPLY_CHEST service failure must be rechecked on resume")
local unsafeServiceState = fixedService:snapshotState()
unsafeServiceState.pendingAction = { kind = "move", direction = "forward" }
unsafeServiceState.poseCertainty = "uncertain"
local unsafeAllowed, unsafeReason = Recovery.classify(unsafeServiceState, fixedServiceCode)
assert(not unsafeAllowed and unsafeReason == "RESUME_STATE_UNSAFE",
    "service retry must still reject uncertain physical actions")
interrupted = fixedService
interruptedState = interrupted:snapshotState()
local servicePose = { x = 0, y = 0, z = 0, facing = 0 }
local serviceTravel, serviceResupply, serviceStages = {}, 0, {}
local executor = InventoryService.new({
    turtle = {
        getItemCount = function() return 0 end,
        getItemDetail = function() return nil end,
        getSelectedSlot = function() return 1 end,
        select = function() return true end,
        transferTo = function() return false end,
        drop = function() return true end,
        inspect = function() return true, { name = "minecraft:chest" } end,
    },
    config = { inventory = { returnThreshold = 14 }, base = {
        acceptedChestBlockIds = { "minecraft:chest" }, separateBulk = false,
    } },
    itemConfig = { retainedItems = {}, bulkItems = {} },
    pose = function() return servicePose end,
    checkpoint = { setService = function(_, value)
        serviceStages[#serviceStages + 1] = value and value.stage or "clear"
        return true
    end },
    progress = function() return interruptedState.progress end,
    route = function() return interruptedState.route end,
    configSnapshot = function() return crashConfig end,
    turnToFacing = function(facing) servicePose.facing = facing; return true end,
    travel = function(target)
        serviceTravel[#serviceTravel + 1] = target
        servicePose.x, servicePose.y, servicePose.z, servicePose.facing =
            target.x, target.y, target.z, target.facing
        return true, "ROUTE_TARGET_REACHED"
    end,
    resupply = function() serviceResupply = serviceResupply + 1; return { ok = true } end,
    report = function() end,
    reportError = function(message) error(message) end,
})
local replayed, replayCode = executor.resume(interruptedState.resumeCheckpoint.pose)
assert(replayed and replayCode == "SERVICE_COMPLETE",
    "coordinator service executor must finish a reloaded interrupted trip")
assert(#serviceTravel == 2 and serviceTravel[1].y == 0
    and serviceTravel[2].y == mainPose.y and serviceResupply == 1,
    "recovery must unload/resupply at base then restore the exact saved checkpoint")
assert(servicePose.x == mainPose.x and servicePose.y == mainPose.y
    and servicePose.z == mainPose.z and servicePose.facing == mainPose.facing
    and serviceStages[#serviceStages] == "clear",
    "service recovery must clear only after exact checkpoint restoration")

local progress = assert(Cursor.mainShaft(1, 1, 0, 1))
local state = {
    status = "mining",
    poseCertainty = "known",
    pendingAction = nil,
    pose = { x = 0, y = -8, z = -13, facing = 0 },
    route = { home = "0,0,0", edges = {
        ["0,-8,-13"] = { ["0,0,0"] = true },
        ["0,0,0"] = { ["0,-8,-13"] = true },
    } },
    progress = progress,
    service = nil,
    vein = nil,
}

local allowed, code = Recovery.classify(state, "STATE_LOADED")
assert(not allowed and code == "MAIN_SHAFT_RESUME_UNSUPPORTED",
    "a known pose must not authorize movement when its cursor cannot restart")

-- A committed pose inside a floor route is not sufficient: until the
-- executor can dispatch that exact next action, resume must remain closed.
local unsupportedCursors = {
assert(Cursor.branch(1, "left", "branch_lower_return", 0, 3, "return_branch_cell", 1)),
}
for _, cursor in ipairs(unsupportedCursors) do
    local active = {}
    for key, value in pairs(state) do active[key] = value end
    active.progress = cursor
    active.resumeCheckpoint = { pose = active.pose, progress = cursor }
    allowed, code = Recovery.classify(active, "STATE_LOADED")
    assert(not allowed and code == "CURSOR_RESUME_UNSUPPORTED",
        "active floor cursor must not be admitted before its exact executor exists")
end

local activeMain = {}
for key, value in pairs(state) do activeMain[key] = value end
activeMain.pose = mainPose
activeMain.configSnapshot = crashConfig
activeMain.resumeCheckpoint = { pose = activeMain.pose, progress = activeMain.progress }
activeMain.floorLandings = { [1] = { landing = { x = 0, y = -8, z = -13, facing = 0 } } }
allowed, code = Recovery.classify(activeMain, "STATE_LOADED")
assert(allowed and code == "RESUME_SAFE_CHECKPOINT",
    "a committed main-shaft cursor with its floor landing is restartable")

local oppositeRoute = { home = mainRoute.home, edges = {} }
for key, neighbors in pairs(mainRoute.edges) do
    oppositeRoute.edges[key] = {}
    for neighbor, connected in pairs(neighbors) do
        oppositeRoute.edges[key][neighbor] = connected
    end
end
for offset = 1, 3 do
    local from = string.format("%d,-8,-13", -(offset - 1))
    local to = string.format("%d,-8,-13", -offset)
    oppositeRoute.edges[from] = oppositeRoute.edges[from] or {}
    oppositeRoute.edges[to] = oppositeRoute.edges[to] or {}
    oppositeRoute.edges[from][to] = true
    oppositeRoute.edges[to][from] = true
end
local opposite = {}
for key, value in pairs(activeMain) do opposite[key] = value end
opposite.route = oppositeRoute
opposite.configSnapshot = {
    branch_length = 30, num_branches = 1, spacing = 3,
    stair_steps_per_floor = 8, pave = false, vein_mine = true,
}
opposite.floorLandings = { [1] = {
    floor = 1, landing = { x = 0, y = -8, z = -13, facing = 0 },
} }
opposite.progress = assert(Cursor.mainSideStart(1, "left"))
opposite.pose = landingPose
opposite.resumeCheckpoint = { pose = landingPose, progress = opposite.progress }
allowed, code = Recovery.classify(opposite, "STATE_LOADED")
assert(allowed, "left-side start must resume from the landing: " .. tostring(code))
opposite.progress = assert(Cursor.mainShaft(1, 2, 0, 1, "left"))
opposite.pose = { x = -1, y = -8, z = -13, facing = 3 }
opposite.resumeCheckpoint = { pose = opposite.pose, progress = opposite.progress }
allowed, code = Recovery.classify(opposite, "STATE_LOADED")
assert(allowed, "left main-shaft cell must resume on its own side: " .. tostring(code))
opposite.progress = assert(Cursor.mainSideReturn(1, "left", 1, 3))
opposite.resumeCheckpoint = {
    pose = { x = -3, y = -8, z = -13, facing = 3 }, progress = opposite.progress,
}
opposite.pose = { x = -1, y = -8, z = -13, facing = 1 }
allowed, code = Recovery.classify(opposite, "STATE_LOADED")
assert(allowed, "left return must resume at a committed intermediate cell: " .. tostring(code))
opposite.pose = { x = 1, y = -8, z = -13, facing = 1 }
allowed, code = Recovery.classify(opposite, "STATE_LOADED")
assert(not allowed and code == "MAIN_SIDE_RETURN_RESUME_UNSUPPORTED",
    "left return must reject a pose on the right side of the landing")
oppositeRoute.edges["-3,-8,-13"]["-3,-8,-12"] = true
oppositeRoute.edges["-3,-8,-12"] = { ["-3,-8,-13"] = true }
opposite.progress = assert(Cursor.branch(1, "left", "branch_outbound_lower",
    1, 3, "mine_branch_cell", 1, "left"))
opposite.pose = { x = -3, y = -8, z = -12, facing = 2 }
opposite.resumeCheckpoint = { pose = opposite.pose, progress = opposite.progress }
allowed, code = Recovery.classify(opposite, "STATE_LOADED")
assert(allowed, "left-main paired shaft must resume on mirrored geometry: " .. tostring(code))
opposite.progress = assert(Cursor.branch(1, "left", "branch_outbound_lower",
    1, 3, "mine_branch_cell", 1, "right"))
opposite.resumeCheckpoint = { pose = opposite.pose, progress = opposite.progress }
allowed, code = Recovery.classify(opposite, "STATE_LOADED")
assert(not allowed and code == "BRANCH_RESUME_UNSUPPORTED",
    "a mirrored shaft pose must not resume under the right-main cursor")

local junctionPose = { x = 6, y = -8, z = -13, facing = 1 }
local junctionRoute = { home = "0,0,0", edges = {
    ["6,-8,-13"] = { ["5,-8,-13"] = true },
    ["5,-8,-13"] = { ["6,-8,-13"] = true, ["4,-8,-13"] = true },
    ["4,-8,-13"] = { ["5,-8,-13"] = true, ["3,-8,-13"] = true },
    ["3,-8,-13"] = { ["4,-8,-13"] = true, ["2,-8,-13"] = true },
    ["2,-8,-13"] = { ["3,-8,-13"] = true, ["1,-8,-13"] = true },
    ["1,-8,-13"] = { ["2,-8,-13"] = true, ["0,-8,-13"] = true },
    ["0,-8,-13"] = { ["1,-8,-13"] = true, ["0,0,0"] = true },
    ["0,0,0"] = { ["0,-8,-13"] = true },
} }
for _, action in ipairs({ "turn_to_left_branch", "restore_main_facing" }) do
    local junctionCursor = assert(Cursor.junction(2, 6, action, 1))
    local junction = {}
    for key, value in pairs(state) do junction[key] = value end
    junction.pose = junctionPose
junction.configSnapshot = crashConfig
    junction.route = junctionRoute
    junction.progress = junctionCursor
    junction.resumeCheckpoint = { pose = junctionPose, progress = junctionCursor }
    junction.floorLandings = { [1] = { landing = { x = 0, y = -8, z = -13, facing = 0 } } }
    allowed, code = Recovery.classify(junction, "STATE_LOADED")
    assert(allowed and code == "RESUME_SAFE_CHECKPOINT",
        "a committed junction action with matching landing and home route is restartable")

    junction.resumeCheckpoint = {
        pose = junctionPose,
        progress = assert(Cursor.junction(2, 6,
            action == "turn_to_left_branch" and "restore_main_facing" or "turn_to_left_branch", 1)),
    }
    allowed, code = Recovery.classify(junction, "STATE_LOADED")
    assert(not allowed and code == "JUNCTION_RESUME_UNSUPPORTED",
        "junction recovery requires the exact next-action cursor")
end

local mismatchedMainCursor = {}
for key, value in pairs(activeMain) do mismatchedMainCursor[key] = value end
mismatchedMainCursor.resumeCheckpoint = {
    pose = activeMain.pose,
    progress = assert(Cursor.mainShaft(1, 2, 0, 1)),
}
allowed, code = Recovery.classify(mismatchedMainCursor, "STATE_LOADED")
assert(not allowed and code == "MAIN_SHAFT_RESUME_UNSUPPORTED",
    "main-shaft recovery must match the complete saved next-action cursor")

local branchCursor = assert(Cursor.branch(1, "left", "branch_outbound_lower", 2,
    3, "mine_branch_cell", 1))
local branchState = {}
for key, value in pairs(state) do branchState[key] = value end
branchState.pose = { x = 3, y = -8, z = -15, facing = 0 }
branchState.progress = branchCursor
branchState.configSnapshot = {
    branch_length = 30, num_branches = 3, spacing = 3,
    stair_steps_per_floor = 8,
}
branchState.floorLandings = { [1] = {
    floor = 1,
    landing = { x = 0, y = -8, z = -13, facing = 0 },
} }
branchState.resumeCheckpoint = { pose = branchState.pose, progress = branchCursor }
branchState.route = { home = "0,0,0", edges = {
    ["3,-8,-15"] = { ["3,-8,-14"] = true },
    ["3,-8,-14"] = { ["3,-8,-15"] = true, ["3,-8,-13"] = true },
    ["3,-8,-13"] = { ["3,-8,-14"] = true, ["2,-8,-13"] = true },
    ["2,-8,-13"] = { ["3,-8,-13"] = true, ["1,-8,-13"] = true },
    ["1,-8,-13"] = { ["2,-8,-13"] = true, ["0,-8,-13"] = true },
    ["0,-8,-13"] = { ["1,-8,-13"] = true, ["0,0,0"] = true },
    ["0,0,0"] = { ["0,-8,-13"] = true },
} }
allowed, code = Recovery.classify(branchState, "STATE_LOADED")
assert(allowed and code == "RESUME_SAFE_CHECKPOINT",
    "a geometrically valid lower-outbound branch cursor with a known home route is resumable")

local returnCursors = {
    { "branch_turnaround", 30, "prepare_branch_return", { x = 3, y = -8, z = -43, facing = 0 } },
    { "branch_upper_return", 12, "scan_and_return_branch_cell", { x = 3, y = -7, z = -25, facing = 2 } },
    { "branch_upper_return", 0, "scan_and_return_branch_cell", { x = 3, y = -7, z = -13, facing = 2 } },
    { "branch_return_to_junction", 0, "descend_to_junction", { x = 3, y = -8, z = -13, facing = 1 } },
}
local function routeToOrigin(pose)
    local route = { home = "0,0,0", edges = {} }
    local current = { x = pose.x, y = pose.y, z = pose.z }
    local function connect(nextPosition)
        local from = string.format("%d,%d,%d", current.x, current.y, current.z)
        local to = string.format("%d,%d,%d", nextPosition.x, nextPosition.y, nextPosition.z)
        route.edges[from] = route.edges[from] or {}
        route.edges[to] = route.edges[to] or {}
        route.edges[from][to] = true
        route.edges[to][from] = true
        current = nextPosition
    end
    while current.y ~= 0 do
        connect({ x = current.x, y = current.y + (current.y < 0 and 1 or -1), z = current.z })
    end
    while current.x ~= 0 do
        connect({ x = current.x + (current.x < 0 and 1 or -1), y = current.y, z = current.z })
    end
    while current.z ~= 0 do
        connect({ x = current.x, y = current.y, z = current.z + (current.z < 0 and 1 or -1) })
    end
    return route
end
for _, item in ipairs(returnCursors) do
    local cursor = assert(Cursor.branch(1, "left", item[1], item[2], 3, item[3], 1))
    local active = {}
    for key, value in pairs(branchState) do active[key] = value end
    active.progress = cursor
    active.pose = item[4]
    active.resumeCheckpoint = { pose = item[4], progress = cursor }
    active.route = routeToOrigin(item[4])
    allowed, code = Recovery.classify(active, "STATE_LOADED")
    assert(allowed and code == "RESUME_SAFE_CHECKPOINT",
        "supported branch return cursor must match its landing-derived pose")
    active.pose = { x = item[4].x, y = item[4].y, z = item[4].z + 1, facing = item[4].facing }
    active.resumeCheckpoint = { pose = active.pose, progress = cursor }
    allowed, code = Recovery.classify(active, "STATE_LOADED")
    assert(not allowed and code == "BRANCH_RESUME_UNSUPPORTED",
        "branch return recovery must reject a geometrically mismatched pose")
end

-- Simulate process restarts at each committed branch phase for both sides.
-- Recovery must preserve the complete serialized cursor and match its pose to
-- the landing-derived branch geometry; either kind of tampering must fail.
local branchCrashCases = {
    { "branch_outbound_lower", 2, "mine_branch_cell", 3 },
    { "branch_turnaround", 30, "prepare_branch_return", 3 },
    { "branch_upper_return", 12, "scan_and_return_branch_cell", 3 },
    { "branch_return_to_junction", 0, "descend_to_junction", 3 },
}
for _, side in ipairs({ "left", "right" }) do
    for index, item in ipairs(branchCrashCases) do
        local cursor = assert(Cursor.branch(1, side, item[1], item[2], 3, item[3], 1))
        local landing = { x = 0, y = -8, z = -13, facing = 0 }
        local grid = assert(require("src.navigation.floor_grid").new(origin, 0,
            { floor = 1, pose = landing }, 8))
        local junction = grid.junction(3)
        local branch = grid.branch(junction, side)
        local traversal = assert(require("src.navigation.branch_traversal").new(branch, 30))
        local pose
        if item[1] == "branch_outbound_lower" then
            pose = assert(traversal.outboundPose(item[2]))
        elseif item[1] == "branch_turnaround" then
            pose = assert(traversal.outboundPose(30))
        elseif item[1] == "branch_upper_return" then
            pose = assert(traversal.upperReturnPose(30 - item[2]))
        else
            pose = assert(traversal.canonicalJunctionPose())
        end
        local path = "crash-branch-" .. side .. "-" .. index .. ".json"
        disk = {}
        local branchRoute = { home = mainRoute.home, edges = {} }
        for key, neighbors in pairs(mainRoute.edges) do
            branchRoute.edges[key] = {}
            for neighbor, connected in pairs(neighbors) do
                branchRoute.edges[key][neighbor] = connected
            end
        end
        local current = { x = landing.x, y = landing.y, z = landing.z }
        local function connectBranchPosition(nextPosition)
            local from = string.format("%d,%d,%d", current.x, current.y, current.z)
            local to = string.format("%d,%d,%d", nextPosition.x, nextPosition.y, nextPosition.z)
            branchRoute.edges[from] = branchRoute.edges[from] or {}
            branchRoute.edges[to] = branchRoute.edges[to] or {}
            branchRoute.edges[from][to], branchRoute.edges[to][from] = true, true
            current = nextPosition
        end
        while current.x ~= pose.x do
            connectBranchPosition({ x = current.x + (pose.x > current.x and 1 or -1),
                y = current.y, z = current.z })
        end
        while current.y ~= pose.y do
            connectBranchPosition({ x = current.x,
                y = current.y + (pose.y > current.y and 1 or -1), z = current.z })
        end
        while current.z ~= pose.z do
            connectBranchPosition({ x = current.x, y = current.y,
                z = current.z + (pose.z > current.z and 1 or -1) })
        end
        local session = assert(Checkpoint.create(crashConfig, pose, branchRoute,
            "crash-branch-" .. side .. "-" .. index, path, fs, textutils))
        local landingInfo = {
            floor = 1, origin = origin,
            mouth = { x = 0, y = 0, z = -4, facing = 0 },
            rear = { x = 0, y = -8, z = -12, facing = 0 },
            landing = landing, steps = 8, entryMoves = 4,
        }
        assert(session:recordFloorLanding(landingInfo, pose, branchRoute, crashConfig))
        assert(session:setProgress(cursor, pose, branchRoute, crashConfig))
        session = nil

        local recovered, loadCode = State.load(path, crashConfig, fs, textutils)
        assert(recovered, "branch restart snapshot must reload: " .. side .. " " .. item[1])
        allowed, code = Recovery.classify(recovered, loadCode)
        assert(allowed and code == "RESUME_SAFE_CHECKPOINT",
            "branch restart must admit its exact committed phase: " .. side .. " " .. item[1]
                .. " " .. tostring(code))

        local tampered = {}
        for key, value in pairs(recovered) do tampered[key] = value end
        tampered.resumeCheckpoint = { pose = pose,
            progress = assert(Cursor.branch(1, side, item[1], item[2], 3, item[3], 2)) }
        allowed, code = Recovery.classify(tampered, loadCode)
        assert(not allowed and code == "BRANCH_RESUME_UNSUPPORTED",
            "branch restart must reject a changed next action: " .. side .. " " .. item[1])

        tampered.resumeCheckpoint = { pose = {
            x = pose.x, y = pose.y, z = pose.z + 1, facing = pose.facing,
        }, progress = cursor }
        allowed, code = Recovery.classify(tampered, loadCode)
        assert(not allowed and code == "BRANCH_RESUME_UNSUPPORTED",
            "branch restart must reject a changed committed pose: " .. side .. " " .. item[1])
    end
end

-- Inject process restarts immediately before and after each logical cursor
-- transition. The previous snapshot must remain the pre-transition cursor;
-- once setProgress commits, reload must expose the complete next cursor.
local transitionPath = "crash-phase-transitions.json"
disk = {}
local transitionPose = mainPose
local transitionRoute = mainRoute
local transitionSession = assert(Checkpoint.create(crashConfig, transitionPose,
    transitionRoute, "crash-phase-transitions", transitionPath, fs, textutils))
local transitionCursor = assert(Cursor.mainShaft(1, 1, 0, 1))
local transitionSequence = {
    { "main_cell_complete", { offset = 1 } },
    { "main_segment_complete" },
    { "branch_started", { side = "left" } },
    { "branch_cell_complete", { offset = 1 } },
    { "outbound_complete" },
    { "upper_return_started", { offset = 1 } },
    { "upper_cell_complete", { offset = 0 } },
    { "upper_return_complete" },
    { "junction_reached" },
    { "main_facing_restored" },
}
assert(transitionSession:setProgress(transitionCursor, transitionPose,
    transitionRoute, crashConfig))
for index, transition in ipairs(transitionSequence) do
    local before, beforeCode = State.load(transitionPath, crashConfig, fs, textutils)
    assert(before and before.progress.phase == transitionCursor.phase
        and before.progress.nextAction == transitionCursor.nextAction,
        "restart before phase transition must retain prior cursor " .. index)
    local nextCursor, transitionCode = Cursor.transition(transitionCursor,
        transition[1], transition[2])
    assert(nextCursor, transitionCode)
    assert(transitionSession:setProgress(nextCursor, transitionPose,
        transitionRoute, crashConfig), "phase transition must commit " .. transition[1])
    transitionSession = nil
    local after, afterCode = State.load(transitionPath, crashConfig, fs, textutils)
    assert(after and after.progress.phase == nextCursor.phase
        and after.progress.nextAction == nextCursor.nextAction,
        "restart after phase transition must expose complete next cursor " .. transition[1])
    assert(Cursor.validate(after.progress), "reloaded transition cursor must validate")
    transitionCursor = nextCursor
    transitionSession = assert(Checkpoint.load(transitionPath, crashConfig, fs, textutils))
end
transitionSession = nil

-- The legacy lower-return transitions remain part of the validated phase
-- machine contract even though the active executor uses the upper return.
local lowerCursor = assert(Cursor.branch(1, "right", "branch_turnaround", 30,
    3, "prepare_branch_return", 1))
local lowerSession = assert(Checkpoint.create(crashConfig, mainPose, mainRoute,
    "crash-lower-phase-transitions", "crash-lower-phase-transitions.json", fs, textutils))
assert(lowerSession:setProgress(lowerCursor, mainPose, mainRoute, crashConfig))
for index, transition in ipairs({
    { "lower_return_started" },
    { "lower_cell_complete", { offset = 1 } },
    { "lower_return_complete" },
}) do
    local prior, priorCode = State.load("crash-lower-phase-transitions.json",
        crashConfig, fs, textutils)
    assert(prior and prior.progress.phase == lowerCursor.phase,
        "restart before lower-return transition must retain prior phase " .. index)
    local nextCursor, transitionCode = Cursor.transition(lowerCursor,
        transition[1], transition[2])
    assert(nextCursor, transitionCode)
    assert(lowerSession:setProgress(nextCursor, mainPose, mainRoute, crashConfig))
    lowerSession = nil
    local after, afterCode = State.load("crash-lower-phase-transitions.json",
        crashConfig, fs, textutils)
    assert(after and after.progress.phase == nextCursor.phase
        and after.progress.nextAction == nextCursor.nextAction
        and Cursor.validate(after.progress),
        "restart after lower-return transition must expose next cursor " .. transition[1])
    lowerCursor = nextCursor
    lowerSession = assert(Checkpoint.load("crash-lower-phase-transitions.json",
        crashConfig, fs, textutils))
end
lowerSession = nil

-- Service restart must preserve the executor's exact cursor, even for the
-- deepest supported branch phases. Exercise every persisted service stage
-- from a committed branch checkpoint and route the resumed target explicitly.
local serviceOrigin = { x = 0, y = 0, z = 0, facing = 0 }
for _, item in ipairs({
    { branchCursor, { x = 3, y = -8, z = -15, facing = 0 } },
    { assert(Cursor.branch(1, "left", "branch_turnaround", 30,
        3, "prepare_branch_return", 1)), { x = 3, y = -8, z = -43, facing = 0 } },
    { assert(Cursor.branch(1, "left", "branch_upper_return", 12,
        3, "scan_and_return_branch_cell", 1)), { x = 3, y = -7, z = -25, facing = 2 } },
    { assert(Cursor.branch(1, "left", "branch_return_to_junction", 0,
        3, "descend_to_junction", 1)), { x = 3, y = -8, z = -13, facing = 1 } },
}) do
    local cursor, checkpointPose = item[1], item[2]
    local serviceState = {}
    for key, value in pairs(branchState) do serviceState[key] = value end
    serviceState.pose = serviceOrigin
    serviceState.progress = cursor
    serviceState.resumeCheckpoint = { pose = checkpointPose, progress = cursor }
    serviceState.route = routeToOrigin(checkpointPose)
    serviceState.floorLandings = branchState.floorLandings
    serviceState.service = {
        stage = "returning", checkpoint = serviceOrigin, resumeProgress = cursor,
    }
    for _, stage in ipairs({ "returning", "at_base", "unloading", "resuming" }) do
        serviceState.service.stage = stage
        allowed, code = Recovery.classify(serviceState, "STATE_LOADED")
        assert(allowed and code == "RESUME_SAFE_SERVICE",
            "service replay should admit " .. cursor.phase .. " at stage " .. stage)
    end
    serviceState.service.resumeProgress = assert(Cursor.branch(1, "left",
        "branch_outbound_lower", 3, 3, "mine_branch_cell", 1))
    allowed, code = Recovery.classify(serviceState, "STATE_LOADED")
    assert(not allowed and code == "SERVICE_RESUME_UNSUPPORTED",
        "service replay must reject a cursor altered during the trip")
end

branchState.pose = { x = 3, y = -8, z = -16, facing = 0 }
branchState.resumeCheckpoint = { pose = branchState.pose, progress = branchCursor }
allowed, code = Recovery.classify(branchState, "STATE_LOADED")
assert(not allowed and code == "BRANCH_RESUME_UNSUPPORTED",
    "branch recovery must reject a pose that differs from the cursor's geometric cell")

local missingMainLanding = {}
for key, value in pairs(activeMain) do missingMainLanding[key] = value end
missingMainLanding.floorLandings = nil
allowed, code = Recovery.classify(missingMainLanding, "STATE_LOADED")
assert(not allowed and code == "MAIN_SHAFT_RESUME_UNSUPPORTED",
    "active main-shaft recovery requires its recorded floor landing")
allowed, code = Recovery.classify(state, "POSITION_UNCERTAIN")
assert(not allowed and code == "POSITION_UNCERTAIN")

local pending = {}
for key, value in pairs(state) do pending[key] = value end
pending.pendingAction = { kind = "move", direction = "forward" }
allowed, code = Recovery.classify(pending, "STATE_LOADED")
assert(not allowed and code == "RESUME_STATE_UNSAFE")

-- Crash injection at the durable intent boundary for every physical action.
for _, intent in ipairs({
    { kind = "move", direction = "forward" },
    { kind = "turn", direction = "left" },
    { kind = "dig", direction = "up" },
}) do
    local interrupted = {}
    for key, value in pairs(activeMain) do interrupted[key] = value end
    interrupted.pendingAction = intent
    allowed, code = Recovery.classify(interrupted, "POSITION_UNCERTAIN")
    assert(not allowed and code == "POSITION_UNCERTAIN",
        "crash after " .. intent.kind .. " intent must remain uncertain")
    allowed, code = Recovery.classify(interrupted, "STATE_LOADED")
    assert(not allowed and code == "RESUME_STATE_UNSAFE",
        "snapshot with pending " .. intent.kind .. " intent must not resume")
end

-- A route edge saved with intent is provisional until the matching physical
-- action and state commit complete; it cannot authorize restart by itself.
for _, record in ipairs({
    { action = "forward", inverse = "back" },
    { action = "turnRight", inverse = "turnLeft" },
}) do
    local interrupted = {}
    for key, value in pairs(activeMain) do interrupted[key] = value end
    interrupted.pendingAction = {
        kind = record.action == "forward" and "move" or "turn",
        direction = record.action == "forward" and "forward" or "right",
    }
    interrupted.routeStack = { records = { record } }
    allowed, code = Recovery.classify(interrupted, "POSITION_UNCERTAIN")
    assert(not allowed and code == "POSITION_UNCERTAIN",
        "crash before route-action commit must stop despite a valid inverse record")
end

local servicing = {}
for key, value in pairs(activeMain) do servicing[key] = value end
servicing.pose = { x = 0, y = 0, z = 0, facing = 0 }
servicing.resumeCheckpoint = { pose = activeMain.pose, progress = activeMain.progress }
servicing.floorLandings = activeMain.floorLandings
servicing.service = {
    stage = "at_base", checkpoint = { x = 0, y = 0, z = 0, facing = 0 },
    resumeProgress = activeMain.progress,
}
allowed, code = Recovery.classify(servicing, "STATE_LOADED")
assert(allowed and code == "RESUME_SAFE_SERVICE",
    "a service checkpoint with a dispatchable cursor and recorded home route is resumable")
for _, stage in ipairs({ "returning", "at_base", "unloading", "resuming" }) do
    servicing.service.stage = stage
    servicing.service.checkpoint = { x = 0, y = 0, z = 0, facing = 0 }
    allowed, code = Recovery.classify(servicing, "STATE_LOADED")
    assert(allowed and code == "RESUME_SAFE_SERVICE", "service stage should be recoverable: " .. stage)
end
servicing.service.resumeProgress = assert(Cursor.mainShaft(1, 2, 0, 1))
allowed, code = Recovery.classify(servicing, "STATE_LOADED")
assert(not allowed and code == "SERVICE_RESUME_UNSUPPORTED",
    "service recovery requires the complete original cursor")
servicing.service.resumeProgress = activeMain.progress
servicing.route = { home = "0,0,0", edges = {} }
allowed, code = Recovery.classify(servicing, "STATE_LOADED")
assert(not allowed and code == "HOME_ROUTE_UNAVAILABLE",
    "service recovery must reject missing recorded return or replay routes")

local vein = {}
for key, value in pairs(state) do vein[key] = value end
local veinCursor = mainCursor
local veinCheckpoint = mainPose
local veinPose = { x = 2, y = -8, z = -13, facing = 1 }
local unwindPose = { x = 1, y = -8, z = -13, facing = 1 }
vein.pose = veinPose
vein.progress = veinCursor
vein.configSnapshot = crashConfig
vein.resumeCheckpoint = { pose = veinCheckpoint, progress = veinCursor }
vein.floorLandings = { [1] = landingRecord }
vein.route = mainRoute
vein.vein = {
    stage = "active", checkpoint = veinCheckpoint,
    visited = { ["0,-8,-13"] = true, ["1,-8,-13"] = true, ["2,-8,-13"] = true },
    frontier = { { next = 1, rotateOnReturn = false }, { next = 1, rotateOnReturn = false } },
    route = { { inverse = "back", facing = 1 }, { inverse = "back", facing = 1 } }, blocks = 3,
}
allowed, code = Recovery.classify(vein, "STATE_LOADED")
assert(allowed and code == "RESUME_SAFE_CHECKPOINT",
    "multiple committed active vein edges with complete inverse routes are resumable for checkpoint unwind: " .. tostring(code))
local unwindingVein = {}
for key, value in pairs(vein) do unwindingVein[key] = value end
unwindingVein.vein = {
    stage = "unwinding", checkpoint = veinCheckpoint,
    visited = { ["0,-8,-13"] = true, ["1,-8,-13"] = true, ["2,-8,-13"] = true },
    frontier = { { next = 1, rotateOnReturn = false } },
    route = { { inverse = "back", facing = 1 } }, blocks = 3,
}
unwindingVein.pose = unwindPose
unwindingVein.resumeCheckpoint = { pose = veinCheckpoint, progress = veinCursor }
unwindingVein.vein.visited["1,-8,-13"] = true
allowed, code = Recovery.classify(unwindingVein, "STATE_LOADED")
assert(allowed and code == "RESUME_SAFE_CHECKPOINT",
    "an interrupted unwind with complete landing and route evidence may resume from its committed intermediate pose")

-- Persist a real unwind boundary, discard the live session, then reload and
-- execute only its remaining inverse breadcrumb. Restart once more after a
-- committed inverse to prove the shortened route and pose stay aligned.
local veinPath = "crash-vein-unwind.json"
disk = {}
local veinSession = assert(Checkpoint.create(crashConfig, unwindPose, mainRoute,
    "crash-vein-unwind", veinPath, fs, textutils))
assert(veinSession:setProgress(mainCursor, mainPose, mainRoute, crashConfig))
assert(veinSession:recordFloorLanding(landingRecord, veinCheckpoint, mainRoute, crashConfig))
assert(veinSession:setProgress(mainCursor, mainPose, mainRoute, crashConfig))
local deeperPose = { x = 2, y = -8, z = -13, facing = 1 }
local serializedUnwind = {}
for key, value in pairs(unwindingVein.vein) do serializedUnwind[key] = value end
serializedUnwind.route = { { inverse = "back", facing = 1 }, { inverse = "back", facing = 1 } }
serializedUnwind.frontier = { { next = 1, rotateOnReturn = false }, { next = 1, rotateOnReturn = false } }
serializedUnwind.visited = { ["0,-8,-13"] = true, ["1,-8,-13"] = true, ["2,-8,-13"] = true }
serializedUnwind.blocks = 3
assert(veinSession:setVein(serializedUnwind, deeperPose, mainRoute, crashConfig))
assert(veinSession:save(deeperPose, mainRoute, crashConfig))
veinSession = nil
local reloadedVeinState, veinLoadCode = State.load(veinPath, crashConfig, fs, textutils)
assert(reloadedVeinState, "interrupted unwind must reload from serialized bytes: " .. tostring(veinLoadCode))
allowed, code = Recovery.classify(reloadedVeinState, veinLoadCode)
assert(allowed and code == "RESUME_SAFE_CHECKPOINT",
    "valid main-shaft cursor admits recorded vein unwind after reload: " .. tostring(code))
local recoveredVeinSession = assert(Checkpoint.load(veinPath, crashConfig, fs, textutils))
local physicalPose = { x = deeperPose.x, y = deeperPose.y, z = deeperPose.z, facing = deeperPose.facing }
local recoveryMoves = 0
local function applyInverse(direction)
    if direction == "back" then
        physicalPose.x = physicalPose.x - 1
    else
        error("unexpected inverse in process-restart fixture: " .. tostring(direction))
    end
    recoveryMoves = recoveryMoves + 1
    return true
end
local firstRecoveryOk = pcall(VeinTraversal.unwindSaved, reloadedVeinState.vein, {
    pose = function() return physicalPose end,
    turn = function() return true end,
    move = applyInverse,
}, function(veinState)
    local saved, saveCode
    if veinState then
        saved, saveCode = recoveredVeinSession:commitVeinAction(
            physicalPose, mainRoute, crashConfig, veinState)
    else
        saved, saveCode = recoveredVeinSession:commitVeinAction(
            physicalPose, mainRoute, crashConfig, nil)
    end
    assert(saved, "each resumed inverse commit must persist: " .. tostring(saveCode))
    if recoveryMoves == 1 then error("INJECTED_PROCESS_RESTART") end
    return true
end)
assert(not firstRecoveryOk and recoveryMoves == 1
    and physicalPose.x == 1 and physicalPose.y == -8 and physicalPose.z == -13,
    "injected restart follows a committed inverse and leaves exact shortened state")
reloadedVeinState, veinLoadCode = State.load(veinPath, crashConfig, fs, textutils)
assert(reloadedVeinState and reloadedVeinState.pose.x == 1
    and #reloadedVeinState.vein.route == 1,
    "second process reload sees the committed intermediate pose and one remaining inverse: "
        .. tostring(veinLoadCode))
allowed, code = Recovery.classify(reloadedVeinState, veinLoadCode)
assert(allowed and code == "RESUME_SAFE_CHECKPOINT",
    "shortened intermediate unwind remains recoverable after another restart: " .. tostring(code))
recoveredVeinSession = assert(Checkpoint.load(veinPath, crashConfig, fs, textutils))
local resumedUnwind = VeinTraversal.unwindSaved(reloadedVeinState.vein, {
    pose = function() return physicalPose end,
    turn = function() return true end,
    move = applyInverse,
}, function(veinState)
    local saved, saveCode = recoveredVeinSession:commitVeinAction(
        physicalPose, mainRoute, crashConfig, veinState)
    assert(saved, "post-restart inverse commit must persist: " .. tostring(saveCode))
    return true
end)
assert(resumedUnwind.ok and recoveryMoves == 2
    and physicalPose.x == veinCheckpoint.x and physicalPose.y == veinCheckpoint.y
    and physicalPose.z == veinCheckpoint.z and physicalPose.facing == veinCheckpoint.facing,
    "post-restart unwind must execute remaining inverse and restore the exact checkpoint")
local afterUnwind, afterUnwindCode = State.load(veinPath, crashConfig, fs, textutils)
assert(afterUnwind and afterUnwind.vein == nil and afterUnwind.pose.x == veinCheckpoint.x,
    "completed resumed unwind clears durable vein state at the exact checkpoint: " .. tostring(afterUnwindCode))

-- If the first inverse fails after restart, no later edge is attempted and
-- the remaining breadcrumb remains available for a safe retry/operator stop.
local failedRecovery = {}
for key, value in pairs(unwindingVein) do failedRecovery[key] = value end
failedRecovery.pose = { x = unwindPose.x, y = unwindPose.y, z = unwindPose.z, facing = unwindPose.facing }
failedRecovery.progress = mainCursor
failedRecovery.resumeCheckpoint = { pose = veinCheckpoint, progress = mainCursor }
disk = {}
local failedSession = assert(Checkpoint.create(crashConfig, failedRecovery.pose, mainRoute,
    "crash-vein-unwind-failure", veinPath, fs, textutils))
assert(failedSession:setProgress(veinCursor, veinCheckpoint, mainRoute, crashConfig))
assert(failedSession:recordFloorLanding(landingRecord, veinCheckpoint, mainRoute, crashConfig))
assert(failedSession:save(failedRecovery.pose, mainRoute, crashConfig))
local serializedFailedUnwind = {}
for key, value in pairs(failedRecovery.vein) do serializedFailedUnwind[key] = value end
serializedFailedUnwind.route = { { inverse = "back", facing = 1 } }
serializedFailedUnwind.visited = { ["0,-8,-13"] = true, ["1,-8,-13"] = true }
serializedFailedUnwind.blocks = 2
assert(failedSession:setVein(serializedFailedUnwind, failedRecovery.pose, mainRoute, crashConfig))
failedSession = nil
local failedSnapshot, failedLoadCode = State.load(veinPath, crashConfig, fs, textutils)
local failedAdmitted, failedRecoveryCode = false, nil
if failedSnapshot then failedAdmitted, failedRecoveryCode = Recovery.classify(failedSnapshot, failedLoadCode) end
assert(failedSnapshot and failedAdmitted and failedRecoveryCode == "RESUME_SAFE_CHECKPOINT",
    "failed-unwind snapshot remains available at an admitted main-shaft checkpoint: "
        .. tostring(failedLoadCode) .. "/" .. tostring(failedRecoveryCode))
local failedMoves = 0
local failedReloadedSession = assert(Checkpoint.load(veinPath, crashConfig, fs, textutils))
local failedResult = VeinTraversal.unwindSaved(failedSnapshot.vein, {
    pose = function() return failedRecovery.pose end,
    turn = function() return true end,
    move = function() failedMoves = failedMoves + 1; return false end,
}, function(veinState)
    local saved = failedReloadedSession:setVein(veinState, failedRecovery.pose, mainRoute, crashConfig)
    return saved == true
end)
assert(not failedResult.ok and failedResult.code == "VEIN_RETURN_BLOCKED" and failedMoves == 1,
    "failed resumed inverse must stop without another physical action")
local failedAfter, failedAfterCode = State.load(veinPath, crashConfig, fs, textutils)
assert(failedAfter and failedAfter.vein and #failedAfter.vein.route == 1
    and failedAfter.pose.x == unwindPose.x,
    "failed inverse must retain its durable route and committed pose: " .. tostring(failedAfterCode))
failedReloadedSession = nil

local enteringVein = {}
for key, value in pairs(vein) do enteringVein[key] = value end
enteringVein.vein = { stage = "entering", checkpoint = veinCheckpoint,
    entryPose = unwindPose, visited = { ["0,-8,-13"] = true }, frontier = {}, route = {}, blocks = 0 }
enteringVein.pose = veinCheckpoint
enteringVein.resumeCheckpoint = { pose = veinCheckpoint, progress = veinCursor }
allowed, code = Recovery.classify(enteringVein, "STATE_LOADED")
assert(not allowed and code == "VEIN_RESUME_UNSUPPORTED",
    "seed-entry snapshots remain refused because dig and movement cannot be distinguished")
local brokenVeinRoute = {}
for key, value in pairs(vein) do brokenVeinRoute[key] = value end
brokenVeinRoute.route = { home = "0,0,0", edges = {
    ["2,-8,-13"] = { ["0,0,0"] = true }, ["0,0,0"] = { ["2,-8,-13"] = true },
} }
allowed, code = Recovery.classify(brokenVeinRoute, "STATE_LOADED")
assert(not allowed and code == "VEIN_RESUME_UNSUPPORTED",
    "vein recovery requires route evidence from every inverse landing to its checkpoint")

local complete = {}
for key, value in pairs(state) do complete[key] = value end
complete.progress = assert(Cursor.floorComplete(1))
complete.resumeCheckpoint = { pose = complete.pose, progress = complete.progress }
complete.floorLandings = { [1] = { landing = complete.pose } }
allowed, code = Recovery.classify(complete, "STATE_LOADED")
assert(allowed and code == "RESUME_SAFE_CHECKPOINT",
    "a completed floor is restartable only with its matching landing checkpoint")
complete.floorLandings = nil
allowed, code = Recovery.classify(complete, "STATE_LOADED")
assert(not allowed and code == "LANDING_RESUME_UNSUPPORTED")

local noHomeRoute = {}
for key, value in pairs(complete) do noHomeRoute[key] = value end
noHomeRoute.floorLandings = { [1] = { landing = noHomeRoute.pose } }
noHomeRoute.route = { home = "0,0,0", edges = {} }
allowed, code = Recovery.classify(noHomeRoute, "STATE_LOADED")
assert(not allowed and code == "HOME_ROUTE_UNAVAILABLE",
    "floor completion must retain a known-clear route home")

local stairCursor = {}
for key, value in pairs(state) do stairCursor[key] = value end
stairCursor.progress = assert(Cursor.stairs(1, 1, "descend_stair_slice"))
stairCursor.routeStack = { records = {
    { action = "forward", inverse = "back" },
    { action = "turnLeft", inverse = "turnRight" },
} }
allowed, code = Recovery.classify(stairCursor, "STATE_LOADED")
assert(not allowed and code == "STAIR_ACTION_PENDING_UNSUPPORTED",
    "a durable inverse stack during a multi-action slice must not permit replay or resume")
stairCursor.pendingAction = { kind = "move", direction = "forward" }
allowed, code = Recovery.classify(stairCursor, "POSITION_UNCERTAIN")
assert(not allowed and code == "POSITION_UNCERTAIN",
    "a crash after stair movement intent must remain uncertain even with its inverse stack persisted")
stairCursor.pendingAction = nil
stairCursor.routeStack = { records = { { action = "forward", inverse = "forward" } } }
allowed, code = Recovery.classify(stairCursor, "STATE_LOADED")
assert(not allowed and code == "ROUTE_STACK_INVALID",
    "invalid durable inverse stacks must be rejected before any recovery movement")
stairCursor.routeStack = nil
allowed, code = Recovery.classify(stairCursor, "STATE_LOADED")
assert(not allowed and code == "STAIR_SLICE_RESUME_UNSUPPORTED",
    "in-slice stair cursors must remain fail closed with a specific recovery reason")

local landingCarve = {}
for key, value in pairs(state) do landingCarve[key] = value end
landingCarve.progress = assert(Cursor.stairs(1, 8, "prepare_landing"))
allowed, code = Recovery.classify(landingCarve, "STATE_LOADED")
assert(not allowed and code == "LANDING_CARVE_RESUME_UNSUPPORTED",
    "landing-carve interruption must remain fail closed with a specific recovery reason")

local surfaceEntry = {}
for key, value in pairs(state) do surfaceEntry[key] = value end
surfaceEntry.pose = { x = 0, y = 0, z = 0, facing = 0 }
surfaceEntry.progress = assert(Cursor.stairs(1, 0, "enter_surface"))
surfaceEntry.resumeCheckpoint = { pose = surfaceEntry.pose, progress = surfaceEntry.progress }
allowed, code = Recovery.classify(surfaceEntry, "STATE_LOADED")
assert(allowed and code == "RESUME_SAFE_CHECKPOINT",
    "surface entry resumes only from its committed origin checkpoint")

local mismatchedResume = {}
for key, value in pairs(surfaceEntry) do mismatchedResume[key] = value end
mismatchedResume.resumeCheckpoint = {
    pose = { x = 0, y = 0, z = -1, facing = 0 },
    progress = mismatchedResume.progress,
}
allowed, code = Recovery.classify(mismatchedResume, "STATE_LOADED")
assert(not allowed and code == "SURFACE_ENTRY_RESUME_UNSUPPORTED",
    "resume descriptor must match the committed physical pose")

local mismatchedCursor = {}
for key, value in pairs(surfaceEntry) do mismatchedCursor[key] = value end
mismatchedCursor.resumeCheckpoint = {
    pose = surfaceEntry.pose,
    progress = assert(Cursor.stairs(1, 0, "prepare_landing")),
}
allowed, code = Recovery.classify(mismatchedCursor, "STATE_LOADED")
assert(not allowed and code == "SURFACE_ENTRY_RESUME_UNSUPPORTED",
    "resume descriptor must match the full next-action cursor, not only its work-unit ID")

local landing = { x = 0, y = -8, z = -13, facing = 0 }
local nextFloorEntry = {}
for key, value in pairs(state) do nextFloorEntry[key] = value end
nextFloorEntry.pose = landing
nextFloorEntry.progress = assert(Cursor.stairs(2, 0, "cross_landing"))
nextFloorEntry.resumeCheckpoint = { pose = landing, progress = nextFloorEntry.progress }
nextFloorEntry.floorLandings = { [1] = {
    floor = 1,
    origin = { x = 0, y = 0, z = 0, facing = 0 },
    mouth = { x = 0, y = 0, z = -4, facing = 0 },
    rear = { x = 0, y = -8, z = -12, facing = 0 },
    landing = landing, steps = 8, entryMoves = 4,
} }
nextFloorEntry.route = { home = "0,0,0", edges = {
    ["0,0,0"] = { ["0,-8,-13"] = true },
    ["0,-8,-13"] = { ["0,0,0"] = true },
} }
allowed, code = Recovery.classify(nextFloorEntry, "STATE_LOADED")
assert(allowed and code == "RESUME_SAFE_CHECKPOINT",
    "cross_landing resumes from the previous saved landing")
local missingPreviousLanding = {}
for key, value in pairs(nextFloorEntry) do missingPreviousLanding[key] = value end
missingPreviousLanding.floorLandings = {}
allowed, code = Recovery.classify(missingPreviousLanding, "STATE_LOADED")
assert(not allowed and code == "LANDING_RESUME_UNSUPPORTED",
    "cross_landing requires complete saved route geometry before recovery")
print("persistence recovery checks passed")
