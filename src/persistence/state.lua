-- Local, schema-checked snapshots for the active single-turtle run.
local State = {}
local SCHEMA_VERSION = 1

local function integer(value)
    return type(value) == "number" and value == math.floor(value)
end

local function poseValid(pose)
    return type(pose) == "table"
        and integer(pose.x) and integer(pose.y) and integer(pose.z)
        and integer(pose.facing) and pose.facing >= 0 and pose.facing <= 3
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local function valid(state)
    return type(state) == "table"
        and state.schemaVersion == SCHEMA_VERSION
        and type(state.runId) == "string" and #state.runId > 0
        and (state.status == "mining" or state.status == "complete" or state.status == "error")
        and (state.poseCertainty == "known" or state.poseCertainty == "uncertain")
        and poseValid(state.pose)
        and type(state.route) == "table"
        and type(state.route.home) == "string"
        and type(state.route.edges) == "table"
        and type(state.configSnapshot) == "table"
        and type(state.configSnapshot.branch_length) == "number"
        and type(state.configSnapshot.num_branches) == "number"
        and type(state.configSnapshot.spacing) == "number"
        and type(state.configSnapshot.pave) == "boolean"
        and type(state.configSnapshot.vein_mine) == "boolean"
        and (state.pendingAction == nil or type(state.pendingAction) == "table")
        and type(state.progress) == "table"
end

local function serialize(state, textutilsApi)
    return textutilsApi.serialize(state, { allow_repetitions = false })
end

local function decode(raw, textutilsApi)
    local ok, value = pcall(textutilsApi.unserialize, raw)
    if not ok or not valid(value) then return nil end
    return value
end

local function readFile(path, fsApi)
    if not fsApi.exists(path) then return nil, "MISSING" end
    local handle = fsApi.open(path, "r")
    if not handle then return nil, "READ_FAILED" end
    local raw = handle.readAll()
    handle.close()
    return raw
end

local function writeFile(path, contents, fsApi)
    local handle = fsApi.open(path, "w")
    if not handle then return false end
    handle.write(contents)
    handle.close()
    return true
end

function State.validate(state)
    return valid(state)
end

function State.new(configSnapshot, pose, route, runId)
    local state = {
        schemaVersion = SCHEMA_VERSION,
        runId = runId,
        status = "mining",
        poseCertainty = "known",
        pose = copy(pose),
        route = copy(route),
        progress = { workDomain = "floor", phase = "active_baseline", nextAction = "continue" },
        pendingAction = nil,
        configSnapshot = copy(configSnapshot),
    }
    if not valid(state) then return nil, "INVALID_STATE" end
    return state
end

function State.save(state, path, fsApi, textutilsApi)
    if not valid(state) then return false, "STATE_INVALID" end
    local tempPath, backupPath = path .. ".tmp", path .. ".bak"
    local encoded = serialize(state, textutilsApi)
    if not encoded or not writeFile(tempPath, encoded, fsApi) then
        return false, "STATE_WRITE_FAILED"
    end
    local checkRaw = readFile(tempPath, fsApi)
    if not checkRaw or not decode(checkRaw, textutilsApi) then
        return false, "STATE_TEMP_INVALID"
    end
    if fsApi.exists(path) then
        local activeRaw = readFile(path, fsApi)
        if not activeRaw or not decode(activeRaw, textutilsApi) then
            return false, "STATE_CORRUPT"
        end
        if fsApi.exists(backupPath) then fsApi.delete(backupPath) end
        fsApi.move(path, backupPath)
    end
    if fsApi.exists(path) then return false, "STATE_ROTATE_FAILED" end
    fsApi.move(tempPath, path)
    if not fsApi.exists(path) then return false, "STATE_COMMIT_FAILED" end
    return true, "STATE_SAVED"
end

function State.load(path, expectedConfig, fsApi, textutilsApi)
    local raw, reason = readFile(path, fsApi)
    local state = raw and decode(raw, textutilsApi) or nil
    local fromBackup = false
    if not state then
        local backupRaw = readFile(path .. ".bak", fsApi)
        state = backupRaw and decode(backupRaw, textutilsApi) or nil
        fromBackup = state ~= nil
    end
    if not state then
        if reason == "MISSING" and not fsApi.exists(path .. ".bak") then
            return nil, "STATE_MISSING"
        end
        return nil, "STATE_CORRUPT"
    end
    local fields = { "branch_length", "num_branches", "spacing", "pave", "vein_mine" }
    for _, field in ipairs(fields) do
        if state.configSnapshot[field] ~= expectedConfig[field] then
            return nil, "CONFIG_MISMATCH"
        end
    end
    if state.pendingAction ~= nil then
        state.poseCertainty = "uncertain"
        return state, "POSITION_UNCERTAIN"
    end
    return state, fromBackup and "STATE_RECOVERED_BACKUP" or "STATE_LOADED"
end

return State
