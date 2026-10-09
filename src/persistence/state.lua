-- Local, schema-checked snapshots for the active single-turtle run.
local State = {}
local SCHEMA_VERSION = 1
local MiningCursor = require("src.mining.cursor")

local function integer(value)
    return type(value) == "number" and value ~= math.huge and value ~= -math.huge
        and value == math.floor(value)
end

local function poseValid(pose)
    return type(pose) == "table"
        and integer(pose.x) and integer(pose.y) and integer(pose.z)
        and integer(pose.facing) and pose.facing >= 0 and pose.facing <= 3
end

local function coordinateKeyValid(key)
    if type(key) ~= "string" then return false end
    local x, y, z = key:match("^(-?%d+),(-?%d+),(-?%d+)$")
    if not x then return false end
    return integer(tonumber(x)) and integer(tonumber(y)) and integer(tonumber(z))
end

local function routeValid(route, pose)
    if type(route) ~= "table" or not coordinateKeyValid(route.home)
        or type(route.edges) ~= "table" or not route.edges[route.home] then
        return false
    end
    local current = pose.x .. "," .. pose.y .. "," .. pose.z
    if not route.edges[current] then return false end
    for fromKey, neighbors in pairs(route.edges) do
        if not coordinateKeyValid(fromKey) or type(neighbors) ~= "table" then return false end
        local fx, fy, fz = fromKey:match("^(-?%d+),(-?%d+),(-?%d+)$")
        fx, fy, fz = tonumber(fx), tonumber(fy), tonumber(fz)
        for toKey, connected in pairs(neighbors) do
            if connected ~= true or not coordinateKeyValid(toKey) then return false end
            local tx, ty, tz = toKey:match("^(-?%d+),(-?%d+),(-?%d+)$")
            tx, ty, tz = tonumber(tx), tonumber(ty), tonumber(tz)
            if math.abs(fx - tx) + math.abs(fy - ty) + math.abs(fz - tz) ~= 1
                or type(route.edges[toKey]) ~= "table"
                or route.edges[toKey][fromKey] ~= true then
                return false
            end
        end
    end
    return true
end

local function floorLandingsValid(landings, route)
    if landings == nil then return true end
    if type(landings) ~= "table" or type(route) ~= "table"
        or type(route.edges) ~= "table" then return false end
    for floor, landing in pairs(landings) do
        if not integer(floor) or floor < 1 or type(landing) ~= "table"
            or landing.floor ~= floor or not poseValid(landing.origin)
            or not poseValid(landing.mouth) or not poseValid(landing.rear)
            or not poseValid(landing.landing) or not integer(landing.steps)
            or landing.steps < 1
            or (landing.entryMoves ~= 4 and landing.entryMoves ~= 1) then
            return false
        end

        local origin, mouth, rear, centre = landing.origin, landing.mouth,
            landing.rear, landing.landing
        local directions = {
            [0] = { x = 0, z = -1 },
            [1] = { x = 1, z = 0 },
            [2] = { x = 0, z = 1 },
            [3] = { x = -1, z = 0 },
        }
        local direction = directions[origin.facing]
        local dx, dz = direction.x, direction.z
        local expectedEntry = floor == 1 and 4 or 1
        if landing.entryMoves ~= expectedEntry
            or (floor == 1 and (origin.x .. "," .. origin.y .. "," .. origin.z) ~= route.home)
            or mouth.x ~= origin.x + dx * expectedEntry
            or mouth.y ~= origin.y or mouth.z ~= origin.z + dz * expectedEntry
            or mouth.facing ~= origin.facing
            or rear.x ~= mouth.x + dx * landing.steps
            or rear.y ~= mouth.y - landing.steps
            or rear.z ~= mouth.z + dz * landing.steps
            or rear.facing ~= origin.facing
            or centre.x ~= rear.x + dx or centre.y ~= rear.y
            or centre.z ~= rear.z + dz or centre.facing ~= origin.facing then
            return false
        end

        for _, pose in ipairs({ origin, mouth, rear, centre }) do
            local key = pose.x .. "," .. pose.y .. "," .. pose.z
            if not route.edges[key] then return false end
        end
    end
    return true
end

local function landingChainValid(landings)
    if type(landings) ~= "table" then return false end
    local count, maximum = 0, 0
    for floor in pairs(landings) do
        if not integer(floor) or floor < 1 then return false end
        count = count + 1
        if floor > maximum then maximum = floor end
    end
    if count == 0 then return true end
    if count ~= maximum or not landings[1] then return false end
    for floor = 2, maximum do
        local previous, current = landings[floor - 1], landings[floor]
        if not previous or not current then return false end
        local a, b = previous.landing, current.origin
        if a.x ~= b.x or a.y ~= b.y or a.z ~= b.z or a.facing ~= b.facing then
            return false
        end
    end
    return true
end

local function pendingActionValid(action)
    if action == nil then return true end
    if type(action) ~= "table" then return false end
    return (action.kind == "move" and (action.direction == "forward" or action.direction == "back"
            or action.direction == "up" or action.direction == "down"))
        or (action.kind == "turn" and (action.direction == "left" or action.direction == "right"))
end

local function configSnapshotValid(config)
    if type(config) ~= "table"
        or not integer(config.branch_length) or config.branch_length <= 0
        or not integer(config.num_branches) or config.num_branches <= 0
        or not integer(config.spacing) or config.spacing < 2
        or type(config.pave) ~= "boolean"
        or type(config.vein_mine) ~= "boolean" then
        return false
    end
    return (config.floor_count == nil or (integer(config.floor_count) and config.floor_count >= 1))
        and (config.stair_steps_per_floor == nil
            or (integer(config.stair_steps_per_floor) and config.stair_steps_per_floor >= 1))
        and (config.surface_entry_length == nil
            or (integer(config.surface_entry_length) and config.surface_entry_length == 4))
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
        and (state.status ~= "error" or type(state.error) == "string")
        and (state.poseCertainty == "known" or state.poseCertainty == "uncertain")
        and poseValid(state.pose)
        and routeValid(state.route, state.pose)
        and floorLandingsValid(state.floorLandings, state.route)
        and landingChainValid(state.floorLandings or {})
        and configSnapshotValid(state.configSnapshot)
        and pendingActionValid(state.pendingAction)
        and MiningCursor.validate(state.progress)
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

function State.validateProgress(progress)
    return MiningCursor.validate(progress)
end

function State.validateFloorLanding(landing, route, existingLandings)
    if type(landing) ~= "table" or not integer(landing.floor) or landing.floor < 1
        or type(existingLandings) ~= "table" then return false end
    local candidate = copy(existingLandings)
    candidate[landing.floor] = copy(landing)
    return floorLandingsValid(candidate, route) and landingChainValid(candidate)
end

function State.new(configSnapshot, pose, route, runId)
    local initialProgress = MiningCursor.initial()
    local state = {
        schemaVersion = SCHEMA_VERSION,
        runId = runId,
        status = "mining",
        poseCertainty = "known",
        pose = copy(pose),
        route = copy(route),
        floorLandings = {},
        progress = initialProgress,
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
    if not configSnapshotValid(expectedConfig) then return nil, "CONFIG_INVALID" end
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
    local fields = {
        "branch_length", "num_branches", "spacing", "pave", "vein_mine",
        "floor_count", "stair_steps_per_floor", "surface_entry_length",
    }
    for _, field in ipairs(fields) do
        if state.configSnapshot[field] ~= nil
            and state.configSnapshot[field] ~= expectedConfig[field] then
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
