local State = require("src.persistence.state")
local Checkpoint = require("src.persistence.checkpoint")
local MiningCursor = require("src.mining.cursor")

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
assert(state.progress.workUnitId == "surface-pair-1-main-1"
    and state.progress.nextAction == "mine_main_cell", "new runs need a concrete next-action cursor")

assert(State.save(state, "state.json", fs, textutils))
local loaded, code = State.load("state.json", config, fs, textutils)
assert(code == "STATE_LOADED" and loaded.runId == "run-1", "roundtrip should preserve state")
state.progress = assert(MiningCursor.junction(1, 1, "turn_to_left_branch"))
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
assertRejectedSnapshot({ progress = { workDomain = "floor", phase = "main_shaft",
    nextAction = "mine_main_cell" } }, "incomplete logical cursor")
local invalidConfig, invalidConfigCode = State.load("state.json", {}, fs, textutils)
assert(invalidConfig == nil and invalidConfigCode == "CONFIG_INVALID", "invalid expected configuration must be rejected")

state.pendingAction = { kind = "move", direction = "forward" }
assert(State.save(state, "pending.json", fs, textutils))
local pending, pendingCode = State.load("pending.json", config, fs, textutils)
assert(pending ~= nil and pendingCode == "POSITION_UNCERTAIN", "pending move must be uncertain")

local mismatched, mismatchCode = State.load("pending.json", { branch_length = 31, num_branches = 20, spacing = 3, pave = false, vein_mine = true }, fs, textutils)
assert(mismatched == nil and mismatchCode == "CONFIG_MISMATCH", "config mismatch must fail closed")

local session = assert(Checkpoint.create(config, pose, route, "run-2", "checkpoint.json", fs, textutils))
assert(session:save(pose, route, config), "checkpoint session should save initial durable state")
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
local invalidProgress = { workDomain = "floor", workUnitId = "bad", phase = "main_shaft",
    nextAction = "mine_main_cell" }
local invalidProgressOk, invalidProgressCode = session:setProgress(invalidProgress, pose, route, config)
assert(not invalidProgressOk and invalidProgressCode == "INVALID_MINING_CURSOR",
    "invalid cursor must be rejected before storage")
local afterRejected = assert(State.load("checkpoint.json", config, fs, textutils))
assert(afterRejected.progress.workUnitId == nextProgress.workUnitId,
    "rejected cursor must not replace the last durable cursor")

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

assert(session:beginAction("move", "forward", pose, route, config), "intent must be checkpointed before action")
local pendingCheckpoint, pendingCheckpointCode = State.load("checkpoint.json", config, fs, textutils)
assert(pendingCheckpoint and pendingCheckpointCode == "POSITION_UNCERTAIN", "checkpoint intent must survive reload")
local movedPose = { x = 0, y = 0, z = -1, facing = 0 }
local movedRoute = { home = "0,0,0", edges = { ["0,0,0"] = { ["0,0,-1"] = true }, ["0,0,-1"] = { ["0,0,0"] = true } } }
assert(session:commitAction(movedPose, movedRoute, config), "successful action commit should save updated live pose")
local committedCheckpoint, committedCode = State.load("checkpoint.json", config, fs, textutils)
assert(committedCode == "STATE_LOADED" and committedCheckpoint.pose.z == -1,
    "commit should clear intent and encode the supplied live pose")
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
