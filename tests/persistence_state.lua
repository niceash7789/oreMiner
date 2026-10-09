local State = require("src.persistence.state")
local Checkpoint = require("src.persistence.checkpoint")
local MiningCursor = require("src.mining.cursor")
local Recovery = require("src.persistence.recovery")

local files = {}
local fs = {
    exists = function(path) return files[path] ~= nil end,
    open = function(path, mode)
        if mode == "r" then
            if files[path] == nil then return nil end
            local value = files[path]
            return { readAll = function() return value end, close = function() end }
        end
        local buffer = ""
        return {
            write = function(value) buffer = buffer .. value end,
            close = function() files[path] = buffer end,
        }
    end,
    delete = function(path) files[path] = nil end,
    move = function(fromPath, toPath)
        assert(files[fromPath] ~= nil, "source exists for move")
        files[toPath], files[fromPath] = files[fromPath], nil
    end,
}

local function encode(value)
    local function atom(item)
        if type(item) == "string" then return string.format("%q", item) end
        if type(item) == "number" or type(item) == "boolean" then return tostring(item) end
        if item == nil then return "nil" end
        local entries = {}
        for key, child in pairs(item) do
            local renderedKey = type(key) == "string" and "[" .. string.format("%q", key) .. "]" or "[" .. tostring(key) .. "]"
            entries[#entries + 1] = renderedKey .. "=" .. atom(child)
        end
        return "{" .. table.concat(entries, ",") .. "}"
    end
    return atom(value)
end
local textutils = { serialize = encode, unserialize = function(raw) return load("return " .. raw)() end }

local config = { branch_length = 30, num_branches = 20, spacing = 3, pave = false, vein_mine = true }
local pose = { x = 0, y = 0, z = 0, facing = 0 }
local route = { home = "0,0,0", edges = { ["0,0,0"] = {} } }
local absent, absentCode = State.load("fresh.json", config, fs, textutils)
assert(absent == nil and absentCode == "STATE_MISSING",
    "only an installation with no active or backup snapshot may start as a new run")
local state = assert(State.new(config, pose, route, "run-1"))
local returnCursor = assert(MiningCursor.branch(1, "left", "branch_upper_return",
    1, 1, "scan_and_return_branch_cell", 1))
local framedReturn = assert(MiningCursor.withWorkUnit(returnCursor,
    { x = 0, y = 1, z = 0, facing = 3 }, {
        branch_length = config.branch_length, num_branches = config.num_branches,
        spacing = config.spacing, floor_count = 1, stair_steps_per_floor = 8,
    }))
assert(framedReturn.outboundFrame == 1,
    "return-phase cursors retain the fixed outbound route frame")
assert(State.validateStatistics({ blocks_mined = 4, active_runtime_seconds = 12.5 }))
assert(not State.validateStatistics({ blocks_mined = -1 }))
assert(not State.validateStatistics({ blocks_mined = 0 / 0 }))
state.statistics = { blocks_mined = 4, ores_mined = 2, active_runtime_seconds = 12.5 }
assert(state.progress.workUnitId == "surface-pair-1-main-1"
    and state.progress.nextAction == "mine_main_cell", "new runs need a concrete next-action cursor")
assert(state.progress.origin.x == pose.x and state.progress.origin.facing == pose.facing
    and state.progress.outboundFrame == pose.facing
    and state.progress.bounds.branchPairLast == config.num_branches
    and state.progress.bounds.offsetLast == config.spacing
    and state.progress.completionStatus == "pending",
    "durable work units must carry their origin, outbound frame, configured bounds, cursor, and status")
assert(state.resumeCheckpoint.pose.x == 0
    and state.resumeCheckpoint.progress.workUnitId == state.progress.workUnitId,
    "new runs need an explicit pose/cursor resume checkpoint")

local fullCursorFields = {
    "workDomain", "workUnitId", "floor", "stairSegment", "stairStep",
    "branchPair", "side", "phase", "offset", "mainOffset", "nextAction",
}
for _, field in ipairs(fullCursorFields) do
    local invalid = State.new(config, pose, route, "cursor-mismatch")
    local different = MiningCursor.stairs(1, 1, "descend_stair_slice")
    invalid.progress = assert(MiningCursor.stairs(1, 2, "descend_stair_slice"))
    invalid.resumeCheckpoint.progress = different
    files["cursor-mismatch.json"] = encode(invalid)
    local rejected, rejectedCode = State.load("cursor-mismatch.json", config, fs, textutils)
    assert(rejected == nil and rejectedCode == "STATE_CORRUPT",
        "resume checkpoint mismatch in " .. field .. " must fail closed")
end

local mismatchedService = State.new(config, pose, route, "service-mismatch")
mismatchedService.progress = assert(MiningCursor.stairs(1, 2, "descend_stair_slice"))
mismatchedService.resumeCheckpoint.progress = mismatchedService.progress
mismatchedService.service = {
    stage = "at_base", checkpoint = pose,
    resumeProgress = assert(MiningCursor.stairs(1, 1, "descend_stair_slice")),
}
files["service-mismatch.json"] = encode(mismatchedService)
local rejectedService, rejectedServiceCode = State.load("service-mismatch.json", config, fs, textutils)
assert(rejectedService == nil and rejectedServiceCode == "STATE_CORRUPT",
    "service checkpoint must match the complete stair cursor")

assert(State.save(state, "state.json", fs, textutils))
local loaded, code = State.load("state.json", config, fs, textutils)
assert(code == "STATE_LOADED" and loaded.runId == "run-1", "roundtrip should preserve state")
assert(loaded.statistics.blocks_mined == 4 and loaded.statistics.active_runtime_seconds == 12.5,
    "checkpoint snapshots must retain validated observational statistics")
assert(loaded.progress.origin.z == 0 and loaded.progress.outboundFrame == 0
    and loaded.progress.bounds.mainOffsetLast == config.num_branches * config.spacing,
    "work-unit metadata must survive checkpoint reload")
local tamperedUnit = State.new(config, pose, route, "tampered-unit")
tamperedUnit.progress.bounds.branchPairLast = config.num_branches + 1
files["tampered-unit.json"] = encode(tamperedUnit)
local rejectedUnit, rejectedUnitCode = State.load("tampered-unit.json", config, fs, textutils)
assert(rejectedUnit == nil and rejectedUnitCode == "STATE_CORRUPT",
    "work-unit bounds that exceed the configured job must fail closed")

local statisticsSession = assert(Checkpoint.create(config, pose, route, "stats-provider", "stats.json", fs, textutils))
assert(statisticsSession:setStatisticsProvider(function()
    return { blocks_mined = 7, active_runtime_seconds = 3 }
end))
assert(statisticsSession:save(pose, route, config))
local savedStats = assert(Checkpoint.load("stats.json", config, fs, textutils))
assert(savedStats:statistics().blocks_mined == 7,
    "regular checkpoint writes must include the live statistics provider")
-- A temp left by a crash during initial creation is recoverable when no active
-- or backup snapshot exists.
local replacementSnapshot = assert(State.new(config, pose, route, "run-after-temp-crash"))
files["first.json.tmp"] = encode(replacementSnapshot)
loaded, code = State.load("first.json", config, fs, textutils)
assert(code == "STATE_LOADED" and loaded.runId == "run-after-temp-crash"
    and files["first.json"] == encode(replacementSnapshot),
    "an initial valid temp snapshot should be promoted")

-- An invalid active file permits a newer validated temp to recover; the valid
-- backup remains preferred over the temp if one exists.
files["recover.json"] = "{broken"
files["recover.json.tmp"] = encode(replacementSnapshot)
loaded, code = State.load("recover.json", config, fs, textutils)
assert(code == "STATE_LOADED" and loaded.runId == "run-after-temp-crash"
    and files["recover.json"] == encode(replacementSnapshot),
    "a validated temp should recover when the active snapshot is corrupt")

files["backup-first.json"] = "{broken"
files["backup-first.json.bak"] = encode(state)
files["backup-first.json.tmp"] = encode(replacementSnapshot)
loaded, code = State.load("backup-first.json", config, fs, textutils)
assert(code == "STATE_RECOVERED_BACKUP" and loaded.runId == "run-1"
    and files["backup-first.json.tmp"] == encode(replacementSnapshot),
    "a valid backup should take precedence over a leftover temp")

files["invalid-temp.json.tmp"] = "{broken"
local noTemp, noTempCode = State.load("invalid-temp.json", config, fs, textutils)
assert(noTemp == nil and noTempCode == "STATE_CORRUPT",
    "a corrupt orphan temp must not be treated as a missing run")

local schemaBadTemp = assert(State.new(config, pose, route, "schema-bad-temp"))
schemaBadTemp.schemaVersion = 99
files["schema-bad-temp.json.tmp"] = encode(schemaBadTemp)
local rejectedTemp, rejectedTempCode = State.load("schema-bad-temp.json", config, fs, textutils)
assert(rejectedTemp == nil and rejectedTempCode == "STATE_CORRUPT",
    "a decodable but schema-invalid temp must not be promoted")

state.progress = assert(MiningCursor.junction(1, 1, "turn_to_left_branch"))
-- Model the checkpoint API's atomic cursor/resume-target update.
state.resumeCheckpoint.progress = state.progress
assert(State.save(state, "state.json", fs, textutils), "second snapshot should rotate the first to backup")

files["state.json"] = "{broken"
local recovered, recoveryCode = State.load("state.json", config, fs, textutils)
assert(recoveryCode == "STATE_RECOVERED_BACKUP" and recovered.runId == "run-1", "backup should recover corruption")

files["state.json"] = encode({ schemaVersion = 99 })
files["state.json.bak"] = encode({ schemaVersion = 99 })
local corrupt, corruptCode = State.load("state.json", config, fs, textutils)
assert(corrupt == nil and corruptCode == "STATE_CORRUPT", "invalid schema must fail closed")
assert(files["state.json"] ~= nil and files["state.json.bak"] ~= nil,
    "failed recovery must leave both unrecognised snapshots available for diagnosis")

local function assertRejectedSnapshot(changes, label)
    local invalid = State.new(config, pose, route, "invalid-run")
    for key, value in pairs(changes) do invalid[key] = value end
    files["invalid.json"] = encode(invalid)
    local rejected, rejectedCode = State.load("invalid.json", config, fs, textutils)
    assert(rejected == nil and rejectedCode == "STATE_CORRUPT", label .. " must fail closed")
end
assertRejectedSnapshot({ status = "running" }, "unknown status enum")
assertRejectedSnapshot({ pose = { x = 0.5, y = 0, z = 0, facing = 0 } }, "fractional pose coordinate")
assertRejectedSnapshot({ route = { home = "0,0,0", edges = { ["0,0,0"] = { ["2,0,0"] = true } } } }, "non-adjacent route edge")
assertRejectedSnapshot({ pendingAction = { kind = "teleport", direction = "forward" } }, "unknown action enum")
assertRejectedSnapshot({ routeStack = { records = { { action = "forward", inverse = "forward" } } } },
    "route record with wrong inverse")
assertRejectedSnapshot({ progress = { workDomain = "floor", phase = "main_shaft",
    nextAction = "mine_main_cell" } }, "incomplete logical cursor")
local invalidConfig, invalidConfigCode = State.load("state.json", {}, fs, textutils)
assert(invalidConfig == nil and invalidConfigCode == "CONFIG_INVALID", "invalid expected configuration must be rejected")

state.pendingAction = { kind = "move", direction = "forward" }
assert(State.save(state, "pending.json", fs, textutils))
local pending, pendingCode = State.load("pending.json", config, fs, textutils)
assert(pending ~= nil and pendingCode == "POSITION_UNCERTAIN", "pending move must be uncertain")

state.pendingAction = { kind = "dig", direction = "up" }
assert(State.save(state, "pending-dig.json", fs, textutils))
local pendingDig, pendingDigCode = State.load("pending-dig.json", config, fs, textutils)
assert(pendingDig ~= nil and pendingDigCode == "POSITION_UNCERTAIN"
    and pendingDig.pendingAction.kind == "dig",
    "pending dig intent must survive reload and prevent automatic resume")
state.pendingAction = nil

local mismatched, mismatchCode = State.load("pending.json", { branch_length = 31, num_branches = 20, spacing = 3, pave = false, vein_mine = true }, fs, textutils)
assert(mismatched == nil and mismatchCode == "CONFIG_MISMATCH", "config mismatch must fail closed")

local session = assert(Checkpoint.create(config, pose, route, "run-2", "checkpoint.json", fs, textutils))
assert(session:save(pose, route, config), "checkpoint session should save initial durable state")
local routeActionStarted, routeActionCode = session:beginRouteAction("forward", "move", "forward",
    pose, route, config)
assert(routeActionStarted, "route action and physical intent should commit atomically: " .. tostring(routeActionCode))
local savedRouteIntent = assert(State.load("checkpoint.json", config, fs, textutils))
assert(savedRouteIntent.pendingAction.kind == "move"
    and savedRouteIntent.routeStack.records[1].action == "forward",
    "a crash after route intent must retain both the action and uncertainty marker")
local forwardPose = { x = 0, y = 0, z = -1, facing = 0 }
local forwardRoute = { home = "0,0,0", edges = {
    ["0,0,0"] = { ["0,0,-1"] = true }, ["0,0,-1"] = { ["0,0,0"] = true },
} }
routeActionStarted, routeActionCode = session:commitRouteAction("back", forwardPose, forwardRoute, config)
assert(routeActionStarted, "inverse commit and route pop should commit atomically: " .. tostring(routeActionCode))
local savedRouteInverse = assert(State.load("checkpoint.json", config, fs, textutils))
assert(savedRouteInverse.pendingAction == nil and #savedRouteInverse.routeStack.records == 0
    and savedRouteInverse.pose.z == -1,
    "a successful inverse should persist pose, clear intent, and pop its route action together")

assert(session:beginRouteAction("turnLeft", "turn", "left", pose, route, config))
assert(session:cancelRouteAction("turnLeft", pose, route, config),
    "literal API failure can clear the provisional stair action safely")
local cancelledRouteAction = assert(State.load("checkpoint.json", config, fs, textutils))
assert(cancelledRouteAction.pendingAction == nil and #cancelledRouteAction.routeStack.records == 0
    and cancelledRouteAction.pose.x == pose.x and cancelledRouteAction.pose.y == pose.y
    and cancelledRouteAction.pose.z == pose.z and cancelledRouteAction.pose.facing == pose.facing,
    "cancelled route action must retain the old pose and remove only its provisional inverse")

local routeFailureWrites = false
local failingRouteFs = {}
for key, value in pairs(fs) do failingRouteFs[key] = value end
failingRouteFs.open = function(path, mode)
    if routeFailureWrites and mode == "w" then return nil end
    return fs.open(path, mode)
end
local atomicSession = assert(Checkpoint.create(config, pose, route, "atomic-run",
    "atomic-route.json", failingRouteFs, textutils))
assert(atomicSession:save(pose, route, config))
routeFailureWrites = true
local failedAtomicIntent = atomicSession:beginRouteAction("forward", "move", "forward",
    pose, route, config)
assert(not failedAtomicIntent, "failed write must not invoke an unrecorded route action")
routeFailureWrites = false
assert(atomicSession:beginRouteAction("forward", "move", "forward", pose, route, config))
routeFailureWrites = true
local failedAtomicInverse = atomicSession:commitRouteAction("back", forwardPose, forwardRoute, config)
assert(not failedAtomicInverse, "failed inverse snapshot must keep its durable predecessor")
routeFailureWrites = false
local failedInverseSnapshot = assert(State.load("atomic-route.json", config, failingRouteFs, textutils))
assert(failedInverseSnapshot.pendingAction ~= nil
    and #failedInverseSnapshot.routeStack.records == 1
    and failedInverseSnapshot.pose.z == 0,
    "failed inverse commit must retain pending intent, old pose, and stack record for certainty stop")
local entryVein = { stage = "entering", checkpoint = pose,
    entryPose = { x = 0, y = 0, z = -1, facing = 0 },
    visited = { ["0,0,0"] = true }, frontier = {}, route = {}, blocks = 0 }
assert(session:setVein(entryVein, pose, route, config), "vein entry intent should be saved before entering ore")
assert(State.validateVein(entryVein, entryVein.entryPose),
    "seed-entry intent should remain valid after the committed seed move")
local savedEntryVein = assert(State.load("checkpoint.json", config, fs, textutils))
assert(savedEntryVein.vein.workDomain == "ore",
    "persisted vein phases must identify the ore work domain")
assert(savedEntryVein.vein.stage == "entering" and savedEntryVein.vein.checkpoint.z == 0,
    "pre-entry vein checkpoint should survive reload")
local safeToResume, recoveryCode = Recovery.classify(savedEntryVein, "STATE_LOADED")
assert(not safeToResume and recoveryCode == "VEIN_RESUME_UNSUPPORTED",
    "restart after the durable vein-entry record must stop before any turtle action")
local activeVein = { stage = "active", checkpoint = pose,
    visited = { ["0,0,0"] = true, ["0,0,-1"] = true },
    frontier = { { next = 2, rotateOnReturn = false } },
    route = { { inverse = "back", facing = 0 } }, blocks = 2 }
local activePose = { x = 0, y = 0, z = -1, facing = 0 }
local activeRoute = { home = "0,0,0", edges = {
    ["0,0,0"] = { ["0,0,-1"] = true }, ["0,0,-1"] = { ["0,0,0"] = true },
} }
local veinCursor = assert(MiningCursor.stairs(1, 0, "enter_surface"))
assert(session:setProgress(veinCursor, pose, route, config),
    "supported tunnel cursor should be checkpointed before the vein excursion")
assert(session:beginAction("move", "forward", pose, route, config),
    "seed movement intent should be durable before the physical move")
assert(session:commitVeinAction(activePose, activeRoute, config, activeVein),
    "successful seed movement and its DFS frontier should commit atomically")
local savedActiveVein = assert(State.load("checkpoint.json", config, fs, textutils))
assert(savedActiveVein.vein.blocks == 2 and savedActiveVein.vein.route[1].inverse == "back"
    and savedActiveVein.pose.z == -1 and savedActiveVein.pendingAction == nil,
    "active vein edge, pose, frontier, and cleared intent should roundtrip together")
safeToResume, recoveryCode = Recovery.classify(savedActiveVein, "STATE_LOADED")
assert(safeToResume and recoveryCode == "RESUME_SAFE_CHECKPOINT",
    "restart after a committed vein edge should admit exact unwind to its supported tunnel cursor")
assert(session:beginAction("move", "up", activePose, activeRoute, config),
    "a vein edge intent should be durable before the physical action")
local interruptedVeinEdge, interruptedVeinCode = State.load("checkpoint.json", config, fs, textutils)
assert(interruptedVeinCode == "POSITION_UNCERTAIN" and interruptedVeinEdge.pendingAction ~= nil,
    "crash after vein edge intent must preserve the uncertainty marker")
safeToResume, recoveryCode = Recovery.classify(interruptedVeinEdge, interruptedVeinCode)
assert(not safeToResume and recoveryCode == "POSITION_UNCERTAIN",
    "an interrupted vein edge must stop as position-uncertain before movement")
assert(session:cancelAction(activePose, activeRoute, config),
    "test fixture can clear the intent after confirming the simulated API failure")
local unwindingVein = {
    stage = "unwinding", checkpoint = pose,
    visited = { ["0,0,0"] = true, ["0,0,-1"] = true },
    frontier = {}, route = { { inverse = "back", facing = 0 } }, blocks = 2,
}
assert(session:setVein(unwindingVein, activePose, activeRoute, config),
    "the unwinding frontier should be durably checkpointed before inverse movement")
local savedUnwindingVein = assert(State.load("checkpoint.json", config, fs, textutils))
safeToResume, recoveryCode = Recovery.classify(savedUnwindingVein, "STATE_LOADED")
assert(not safeToResume and recoveryCode == "VEIN_RESUME_UNSUPPORTED",
    "restart during vein unwind must stop instead of guessing which inverse edge completed")
assert(session:beginAction("move", "back", activePose, activeRoute, config),
    "final inverse intent should be durable before returning to the checkpoint")
assert(session:commitVeinAction(pose, route, config, nil),
    "the last inverse move and excursion clear should commit atomically")
local savedClearedVein = assert(State.load("checkpoint.json", config, fs, textutils))
assert(savedClearedVein.vein == nil and savedClearedVein.pose.z == 0
    and savedClearedVein.pendingAction == nil,
    "exact checkpoint pose and cleared excursion should share the final snapshot")
assert(not session:setVein({ stage = "active", checkpoint = pose,
    visited = { ["0,0,-1"] = true }, frontier = { { next = 2, rotateOnReturn = false } },
    route = { { inverse = "back", facing = 0 } }, blocks = 2 }, activePose, activeRoute, config),
    "active vein state must include the checkpoint coordinate in its visited set")
assert(session:setVein(nil, pose, route, config), "completed excursion should clear its durable record")
local stackOk, stackCode = session:recordRouteAction("forward", pose, route, config)
assert(stackOk, "a reversible route action should be durably recorded: " .. tostring(stackCode))
stackOk, stackCode = session:recordRouteAction("turnRight", pose, route, config)
assert(stackOk, "a second route action should be durably recorded: " .. tostring(stackCode))
local savedStack = assert(State.load("checkpoint.json", config, fs, textutils))
assert(savedStack.routeStack.records[1].inverse == "back"
    and savedStack.routeStack.records[2].inverse == "turnLeft",
    "route actions and inverses should survive snapshot reload in order")
local stackCopy = session:routeStack()
stackCopy.records[1].action = "dig"
assert(session:routeStack().records[1].action == "forward",
    "route stack getter must return a defensive copy")
local badStackOk, badStackCode = session:recordRouteAction("dig", pose, route, config)
assert(not badStackOk and badStackCode == "INVALID_ROUTE_ACTION",
    "non-reversible actions must not enter the persisted route stack")
local inverseOk, inverseCode = session:commitRouteInverse("back", pose, route, config)
assert(not inverseOk and inverseCode == "ROUTE_STACK_MISMATCH",
    "only the exact top inverse may be committed")
assert(session:commitRouteInverse("turnLeft", pose, route, config),
    "successful inverse may retire only its matching top record")
local unwoundOne = assert(State.load("checkpoint.json", config, fs, textutils))
assert(#unwoundOne.routeStack.records == 1
    and unwoundOne.routeStack.records[1].action == "forward",
    "committed unwind must persist the remaining route prefix")
assert(session:commitRouteInverse("back", pose, route, config))
local unwoundAll = assert(State.load("checkpoint.json", config, fs, textutils))
assert(#unwoundAll.routeStack.records == 0, "complete unwind must persist an empty stack")
local landingRoute = {
    floor = 1,
    origin = { x = 0, y = 0, z = 0, facing = 0 },
    mouth = { x = 0, y = 0, z = -4, facing = 0 },
    rear = { x = 0, y = -8, z = -12, facing = 0 },
    landing = { x = 0, y = -8, z = -13, facing = 0 },
    steps = 8,
    entryMoves = 4,
}
local landingGraph = { home = "0,0,0", edges = {} }
for _, point in ipairs({ landingRoute.origin, landingRoute.mouth,
    landingRoute.rear, landingRoute.landing }) do
    landingGraph.edges[point.x .. "," .. point.y .. "," .. point.z] = {}
end
assert(State.validateFloorLanding(landingRoute, landingGraph, {}),
    "a geometrically consistent floor landing route should validate")
assert(not State.validateFloorLanding({
    floor = 1, origin = landingRoute.origin, mouth = landingRoute.mouth,
    rear = landingRoute.rear, landing = { x = 0, y = -8, z = -14, facing = 0 },
    steps = 8, entryMoves = 4,
}, landingGraph, {}), "a landing pose beyond the recorded rear cell must fail")
local landingSession = assert(Checkpoint.create(config, landingRoute.landing, landingGraph,
    "run-landing", "landing-checkpoint.json", fs, textutils))
assert(landingSession:recordFloorLanding(landingRoute, landingRoute.landing, landingGraph, config),
    "landing route should be durably recorded")
local savedLanding = assert(State.load("landing-checkpoint.json", config, fs, textutils))
assert(savedLanding.floorLandings[1].landing.z == -13,
    "roundtrip should retain the canonical floor landing pose")
local conflictingLanding = {
    floor = 1,
    origin = { x = 0, y = 0, z = 0, facing = 1 },
    mouth = { x = 4, y = 0, z = 0, facing = 1 },
    rear = { x = 12, y = -8, z = 0, facing = 1 },
    landing = { x = 13, y = -8, z = 0, facing = 1 },
    steps = 8, entryMoves = 4,
}
for _, point in ipairs({ conflictingLanding.origin, conflictingLanding.mouth,
    conflictingLanding.rear, conflictingLanding.landing }) do
    landingGraph.edges[point.x .. "," .. point.y .. "," .. point.z] = {}
end
local conflictOk, conflictCode = landingSession:recordFloorLanding(conflictingLanding,
    landingRoute.landing, landingGraph, config)
assert(not conflictOk and conflictCode == "LANDING_CONFLICT",
    "a different landing pose must not overwrite the saved floor route")
assert(landingSession:floorLanding(1).landing.z == -13,
    "rejected route replacement must preserve the saved landing")

local nextProgress = {
    workDomain = "floor",
    workUnitId = "surface-pair-2-left-branch_outbound_lower-3",
    floor = 0,
    stairSegment = 0,
    stairStep = 0,
    branchPair = 2,
    side = "left",
    phase = "branch_outbound_lower",
    offset = 3,
    mainOffset = 2,
    nextAction = "mine_branch_cell",
}
local nextProgressOk, nextProgressCode = session:setProgress(nextProgress, pose, route, config)
assert(nextProgressOk, "logical cursor update should be durable: " .. tostring(nextProgressCode))
local progressed, progressedCode = State.load("checkpoint.json", config, fs, textutils)
assert(progressedCode == "STATE_LOADED" and progressed.progress.workUnitId == nextProgress.workUnitId
    and progressed.progress.offset == 3, "saved cursor should describe the next bounded work unit")
assert(progressed.resumeCheckpoint.pose.x == pose.x
    and progressed.resumeCheckpoint.progress.workUnitId == nextProgress.workUnitId,
    "resume checkpoint must atomically track the committed pose and next cursor")
assert(session:recordTorchPlacement("floor-1-stair-4", pose, route, config),
    "torch placement key should be committed with the state snapshot")
assert(session:hasTorchPlacement("floor-1-stair-4"), "committed torch key should suppress duplicates")
local litReload = assert(Checkpoint.load("checkpoint.json", config, fs, textutils))
assert(litReload:hasTorchPlacement("floor-1-stair-4"), "torch placement key should survive reload")
assert(not litReload:hasTorchPlacement("floor-1-stair-5"), "unplaced route distance should remain eligible")
local serviceRecord = { stage = "returning", checkpoint = pose, resumeProgress = nextProgress }
assert(session:setService(serviceRecord, pose, route, config), "service checkpoint must be durable")
local savedService = assert(State.load("checkpoint.json", config, fs, textutils))
assert(savedService.service.stage == "returning"
    and savedService.service.checkpoint.x == pose.x
    and savedService.service.workDomain == "service",
    "service stage and mining checkpoint should survive reload")
local serviceView = session:service()
serviceView.stage = "unloading"
assert(session:service().stage == "returning", "service getter must return a defensive copy")
assert(session:setService({ stage = "at_base", checkpoint = pose,
    resumeProgress = nextProgress }, pose, route, config), "service stage should advance durably")
local resumeView = session:resumeCheckpoint()
resumeView.progress.workUnitId = "mutated"
assert(session:resumeCheckpoint().progress.workUnitId == nextProgress.workUnitId,
    "resume checkpoint getter must return a defensive copy")
local invalidProgress = { workDomain = "floor", workUnitId = "bad", phase = "main_shaft",
    nextAction = "mine_main_cell" }
local invalidProgressOk, invalidProgressCode = session:setProgress(invalidProgress, pose, route, config)
assert(not invalidProgressOk and invalidProgressCode == "INVALID_MINING_CURSOR",
    "invalid cursor must be rejected before storage")
local afterRejected = assert(State.load("checkpoint.json", config, fs, textutils))
assert(afterRejected.progress.workUnitId == nextProgress.workUnitId,
    "rejected cursor must not replace the last durable cursor")

assertRejectedSnapshot({ resumeCheckpoint = { pose = pose,
    progress = assert(MiningCursor.mainShaft(2, 1, 1)) } },
    "resume checkpoint cursor inconsistent with active progress")
assertRejectedSnapshot({ service = { stage = "departing", checkpoint = pose,
    resumeProgress = nextProgress } }, "unknown service stage")

local failWrites = true
local failingFs = {}
for key, value in pairs(fs) do failingFs[key] = value end
failingFs.open = function(path, mode)
    if mode == "w" and failWrites then return nil end
    return fs.open(path, mode)
end
local failingSession = assert(Checkpoint.create(config, pose, route, "run-failed-progress",
    "failed-progress.json", failingFs, textutils))
local failedProgressOk, failedProgressCode = failingSession:setProgress(nextProgress, pose, route, config)
assert(not failedProgressOk and failedProgressCode == "STATE_WRITE_FAILED",
    "cursor write failure should stop the update")
failWrites = false
assert(failingSession:save(pose, route, config), "session should remain usable after cursor write failure")
local afterFailedWrite = assert(State.load("failed-progress.json", config, fs, textutils))
assert(afterFailedWrite.progress.workUnitId == "surface-pair-1-main-1",
    "failed cursor write must retain the previous in-memory cursor")
assert(failingSession:resumeCheckpoint().progress.workUnitId == "surface-pair-1-main-1",
    "failed cursor write must retain the previous resume checkpoint")

assert(session:beginAction("move", "forward", pose, route, config), "intent must be checkpointed before action")
local pendingCheckpoint, pendingCheckpointCode = State.load("checkpoint.json", config, fs, textutils)
assert(pendingCheckpoint and pendingCheckpointCode == "POSITION_UNCERTAIN", "checkpoint intent must survive reload")
local movedPose = { x = 0, y = 0, z = -1, facing = 0 }
local movedRoute = { home = "0,0,0", edges = { ["0,0,0"] = { ["0,0,-1"] = true }, ["0,0,-1"] = { ["0,0,0"] = true } } }
assert(session:commitVeinAction(movedPose, movedRoute, config, activeVein),
    "successful vein edge should commit pose and DFS state together")
local committedCheckpoint, committedCode = State.load("checkpoint.json", config, fs, textutils)
assert(committedCode == "STATE_LOADED" and committedCheckpoint.pose.z == -1,
    "commit should clear intent and encode the supplied live pose")
assert(committedCheckpoint.vein.blocks == 2 and committedCheckpoint.vein.route[1].inverse == "back",
    "the same edge commit must include its matching vein frontier and breadcrumb")
assert(session:beginAction("move", "back", movedPose, movedRoute, config),
    "inverse movement intent must be saved before returning to the vein checkpoint")
assert(session:commitVeinAction(pose, route, config, nil),
    "arrival at the exact checkpoint should atomically commit pose and clear the vein record")
local clearedVeinCheckpoint, clearedVeinCode = State.load("checkpoint.json", config, fs, textutils)
assert(clearedVeinCode == "STATE_LOADED" and clearedVeinCheckpoint.pendingAction == nil
    and clearedVeinCheckpoint.vein == nil and clearedVeinCheckpoint.pose.z == 0,
    "checkpoint arrival must clear pending intent and vein state in the same snapshot")

local failedVeinSession = assert(Checkpoint.create(config, pose, route, "run-failed-vein",
    "failed-vein.json", failingFs, textutils))
failWrites = false
assert(failedVeinSession:save(pose, route, config), "vein failure fixture should save its baseline")
assert(failedVeinSession:beginAction("move", "forward", pose, route, config),
    "vein failure fixture should persist the movement intent")
failWrites = true
local failedVeinCommit, failedVeinCode = failedVeinSession:commitVeinAction(
    movedPose, movedRoute, config, activeVein)
assert(not failedVeinCommit and failedVeinCode == "STATE_WRITE_FAILED",
    "failed combined edge snapshot must be reported")
local retainedPending, retainedPendingCode = State.load("failed-vein.json", config, fs, textutils)
assert(retainedPendingCode == "POSITION_UNCERTAIN" and retainedPending.pendingAction ~= nil,
    "failed combined edge snapshot must leave the prior pending intent durable")
failWrites = false
local retainedMemory = failedVeinSession:vein()
assert(retainedMemory == nil, "failed edge commit must roll back its in-memory vein state")

assert(session:markFatal("TEST_STOP", movedPose, movedRoute, config), "fatal state should be checkpointed")
assert(session:status() == "error", "checkpoint session should expose status without exposing mutations")
local fatalCheckpoint, fatalCode = State.load("checkpoint.json", config, fs, textutils)
assert(fatalCode == "STATE_LOADED" and fatalCheckpoint.status == "error"
    and fatalCheckpoint.error == "TEST_STOP", "fatal error code must persist before the run stops")

local function coordinateKey(value)
    return value.x .. "," .. value.y .. "," .. value.z
end
local stairGraph = { home = "0,0,0", edges = { ["0,0,0"] = {} } }
local function edge(from, to)
    local fromKey, toKey = coordinateKey(from), coordinateKey(to)
    stairGraph.edges[fromKey] = stairGraph.edges[fromKey] or {}
    stairGraph.edges[toKey] = stairGraph.edges[toKey] or {}
    stairGraph.edges[fromKey][toKey] = true
    stairGraph.edges[toKey][fromKey] = true
end
local function segment(floor, origin, entryMoves, steps)
    local current = { x = origin.x, y = origin.y, z = origin.z, facing = origin.facing }
    for _ = 1, entryMoves do
        local nextPose = { x = current.x, y = current.y, z = current.z - 1, facing = current.facing }
        edge(current, nextPose)
        current = nextPose
    end
    local mouth = { x = current.x, y = current.y, z = current.z, facing = current.facing }
    for _ = 1, steps do
        local nextPose = { x = current.x, y = current.y, z = current.z - 1, facing = current.facing }
        edge(current, nextPose)
        current = nextPose
        nextPose = { x = current.x, y = current.y - 1, z = current.z, facing = current.facing }
        edge(current, nextPose)
        current = nextPose
    end
    local rear = { x = current.x, y = current.y, z = current.z, facing = current.facing }
    local landing = { x = current.x, y = current.y, z = current.z - 1, facing = current.facing }
    edge(current, landing)
    return { floor = floor, origin = origin, mouth = mouth, rear = rear,
        landing = landing, steps = steps, entryMoves = entryMoves }
end

local routeOne = segment(1, pose, 4, 8)
local stairSession = assert(Checkpoint.create(config, routeOne.landing, stairGraph,
    "stair-run", "stair-checkpoint.json", fs, textutils))
assert(stairSession:recordFloorLanding(routeOne, routeOne.landing, stairGraph, config),
    "first landing route should persist")
local routeTwo = segment(2, routeOne.landing, 1, 8)
local orphanSession = assert(Checkpoint.create(config, routeTwo.landing, stairGraph,
    "orphan-stair-run", "orphan-stair-checkpoint.json", fs, textutils))
local orphanOk, orphanCode = orphanSession:recordFloorLanding(routeTwo,
    routeTwo.landing, stairGraph, config)
assert(not orphanOk and orphanCode == "INVALID_FLOOR_LANDING",
    "a later floor landing must not be recorded without its preceding floor")
assert(stairSession:recordFloorLanding(routeTwo, routeTwo.landing, stairGraph, config),
    "second landing route should persist after the first")
assert(stairSession:floorLanding(2).landing.z == -23
    and stairSession:floorLandings()[1].landing.z == -13,
    "checkpoint getters should return saved landing routes")
local loadedStairs = assert(State.load("stair-checkpoint.json", config, fs, textutils))
assert(loadedStairs.floorLandings[2].landing.y == -16,
    "landing routes should survive snapshot reload")
local skippedLanding = {}
for key, value in pairs(loadedStairs) do skippedLanding[key] = value end
skippedLanding.floorLandings = { [2] = loadedStairs.floorLandings[2] }
assert(not State.validate(skippedLanding), "floor landing records must not skip earlier floors")
local invalidRoute = {}
for key, value in pairs(routeTwo) do invalidRoute[key] = value end
invalidRoute.landing = { x = 0, y = -16, z = -24, facing = 0 }
local invalidRouteOk, invalidRouteCode = stairSession:recordFloorLanding(invalidRoute,
    routeTwo.landing, stairGraph, config)
assert(not invalidRouteOk and invalidRouteCode == "INVALID_FLOOR_LANDING",
    "inconsistent landing geometry must not replace saved routes")

print("persistence state checks passed")
