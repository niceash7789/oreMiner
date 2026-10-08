local State = require("src.persistence.state")
local Checkpoint = require("src.persistence.checkpoint")

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

assert(State.save(state, "state.json", fs, textutils))
local loaded, code = State.load("state.json", config, fs, textutils)
assert(code == "STATE_LOADED" and loaded.runId == "run-1", "roundtrip should preserve state")
state.progress.nextAction = "next"
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
print("persistence state checks passed")
