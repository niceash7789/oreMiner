-- Local, schema-checked snapshots for the active single-turtle run.
local State = {}
local SCHEMA_VERSION = 1
local MiningCursor = require("src.mining.cursor")
local ActionStack = require("src.navigation.action_stack")

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
        or (action.kind == "dig" and (action.direction == "forward"
            or action.direction == "up" or action.direction == "down"))
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

local function sameValue(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do
        if not sameValue(value, right[key]) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function workUnitValid(progress)
    if progress.origin == nil and progress.bounds == nil
        and progress.outboundFrame == nil and progress.completionStatus == nil then
        return true -- Existing schema-1 snapshots remain readable.
    end
    local origin, bounds = progress.origin, progress.bounds
    local expectedFrame = poseValid(origin) and origin.facing or nil
    if expectedFrame ~= nil and (progress.phase == "branch_upper_return"
        or progress.phase == "branch_lower_return"
        or progress.phase == "branch_return_to_junction") then
        expectedFrame = (expectedFrame + 2) % 4
    end
    return poseValid(origin) and progress.outboundFrame == expectedFrame
        and (progress.completionStatus == "pending" or progress.completionStatus == "complete")
        and type(bounds) == "table"
        and integer(bounds.floorFirst) and bounds.floorFirst >= 0
        and integer(bounds.floorLast) and bounds.floorLast >= bounds.floorFirst
        and integer(bounds.branchPairFirst) and bounds.branchPairFirst >= 1
        and integer(bounds.branchPairLast) and bounds.branchPairLast >= bounds.branchPairFirst
        and integer(bounds.offsetFirst) and bounds.offsetFirst >= 0
        and integer(bounds.offsetLast) and bounds.offsetLast >= bounds.offsetFirst
        and integer(bounds.mainOffsetFirst) and bounds.mainOffsetFirst >= 0
        and integer(bounds.mainOffsetLast) and bounds.mainOffsetLast >= bounds.mainOffsetFirst
        and integer(bounds.stairStepFirst) and bounds.stairStepFirst >= 1
        and integer(bounds.stairStepLast) and bounds.stairStepLast >= bounds.stairStepFirst
        and progress.floor >= bounds.floorFirst and progress.floor <= bounds.floorLast
        and progress.branchPair >= bounds.branchPairFirst
        and progress.branchPair <= bounds.branchPairLast
        and progress.offset >= bounds.offsetFirst and progress.offset <= bounds.offsetLast
        and progress.mainOffset >= bounds.mainOffsetFirst
        and progress.mainOffset <= bounds.mainOffsetLast
        and (progress.phase ~= "stairs" or progress.stairStep <= bounds.stairStepLast)
end

local function lightingValid(lighting)
    if lighting == nil then return true end
    if type(lighting) ~= "table" or type(lighting.placed) ~= "table" then return false end
    local count = 0
    for key, value in pairs(lighting.placed) do
        if type(key) ~= "string" or #key == 0 or value ~= true then return false end
        count = count + 1
        if count > 4096 then return false end
    end
    return true
end

local function statisticsValid(statistics)
    if statistics == nil then return true end
    if type(statistics) ~= "table" then return false end
    local count = 0
    for key, value in pairs(statistics) do
        if type(key) ~= "string" or #key == 0 or #key > 128
            or type(value) ~= "number" or value ~= value
            or value == math.huge or value == -math.huge or value < 0 then
            return false
        end
        count = count + 1
        if count > 128 then return false end
    end
    return true
end

local function resumeCheckpointValid(checkpoint, progress)
    return type(checkpoint) == "table" and poseValid(checkpoint.pose)
        and MiningCursor.validate(checkpoint.progress)
        and checkpoint.progress.workDomain == progress.workDomain
        and checkpoint.progress.workUnitId == progress.workUnitId
        and checkpoint.progress.floor == progress.floor
        and checkpoint.progress.stairSegment == progress.stairSegment
        and checkpoint.progress.stairStep == progress.stairStep
        and checkpoint.progress.branchPair == progress.branchPair
        and checkpoint.progress.side == progress.side
        and checkpoint.progress.phase == progress.phase
        and checkpoint.progress.offset == progress.offset
        and checkpoint.progress.mainOffset == progress.mainOffset
        and checkpoint.progress.nextAction == progress.nextAction
        and (checkpoint.progress.origin == nil or workUnitValid(checkpoint.progress))
        and (progress.origin == nil or workUnitValid(progress))
        and sameValue(checkpoint.progress.origin, progress.origin)
        and sameValue(checkpoint.progress.outboundFrame, progress.outboundFrame)
        and sameValue(checkpoint.progress.bounds, progress.bounds)
        and sameValue(checkpoint.progress.completionStatus, progress.completionStatus)
end

local SERVICE_STAGES = {
    returning = true,
    at_base = true,
    unloading = true,
    resuming = true,
}

local function serviceValid(service, progress)
    if service == nil then return true end
    return type(service) == "table"
        and (service.workDomain == nil or service.workDomain == "service")
        and SERVICE_STAGES[service.stage] == true
        and poseValid(service.checkpoint)
        and type(service.resumeProgress) == "table"
        and MiningCursor.validate(service.resumeProgress)
        and service.resumeProgress.workDomain == progress.workDomain
        and service.resumeProgress.workUnitId == progress.workUnitId
        and service.resumeProgress.stairSegment == progress.stairSegment
        and service.resumeProgress.stairStep == progress.stairStep
        and service.resumeProgress.branchPair == progress.branchPair
        and service.resumeProgress.side == progress.side
        and service.resumeProgress.phase == progress.phase
        and service.resumeProgress.offset == progress.offset
        and service.resumeProgress.mainOffset == progress.mainOffset
        and service.resumeProgress.nextAction == progress.nextAction
        and service.resumeProgress.floor == progress.floor
        and workUnitValid(service.resumeProgress)
        and sameValue(service.resumeProgress.origin, progress.origin)
        and sameValue(service.resumeProgress.outboundFrame, progress.outboundFrame)
        and sameValue(service.resumeProgress.bounds, progress.bounds)
        and sameValue(service.resumeProgress.completionStatus, progress.completionStatus)
end

local function veinValid(vein, pose)
    if vein == nil then return true end
    if type(vein) ~= "table" or not poseValid(vein.checkpoint)
        or (vein.workDomain ~= nil and vein.workDomain ~= "ore")
        or (vein.stage ~= "entering" and vein.stage ~= "active" and vein.stage ~= "unwinding")
        or type(vein.visited) ~= "table" or type(vein.frontier) ~= "table"
        or type(vein.route) ~= "table" or not integer(vein.blocks)
        or vein.blocks < 0 or vein.blocks > 64 or #vein.route > 9 or #vein.frontier > 65 then
        return false
    end
    local visitedCount = 0
    for coordinate, value in pairs(vein.visited) do
        if not coordinateKeyValid(coordinate) or value ~= true then return false end
        visitedCount = visitedCount + 1
    end
    if visitedCount ~= vein.blocks and vein.stage ~= "entering" then return false end
    if vein.stage == "entering" then
        if not poseValid(vein.entryPose) then return false end
        local checkpoint = vein.checkpoint
        local entry = vein.entryPose
        local displacement = math.abs(entry.x - checkpoint.x)
            + math.abs(entry.y - checkpoint.y) + math.abs(entry.z - checkpoint.z)
        return vein.blocks == 0 and #vein.route == 0 and #vein.frontier == 0
            and displacement == 1 and entry.facing == checkpoint.facing
            and (pose.x == checkpoint.x and pose.y == checkpoint.y and pose.z == checkpoint.z
                or pose.x == entry.x and pose.y == entry.y and pose.z == entry.z)
            and vein.visited[checkpoint.x .. "," .. checkpoint.y .. "," .. checkpoint.z] == true
    end
    if vein.blocks < 1 or #vein.route < 1
        or (vein.stage == "active" and #vein.frontier < 1) then return false end
    for _, breadcrumb in ipairs(vein.route) do
        if type(breadcrumb) ~= "table"
            or (breadcrumb.inverse ~= "back" and breadcrumb.inverse ~= "up" and breadcrumb.inverse ~= "down")
            or not integer(breadcrumb.facing) or breadcrumb.facing < 0 or breadcrumb.facing > 3 then
            return false
        end
    end
    for _, frame in ipairs(vein.frontier) do
        if type(frame) ~= "table" or not integer(frame.next) or frame.next < 1 or frame.next > 7
            or type(frame.rotateOnReturn) ~= "boolean" then return false end
    end
    return vein.visited[pose.x .. "," .. pose.y .. "," .. pose.z] == true
end

local function valid(state)
    return type(state) == "table"
        and state.schemaVersion == SCHEMA_VERSION
        and type(state.runId) == "string" and #state.runId > 0
        and (state.status == "mining" or state.status == "paused"
            or state.status == "complete" or state.status == "error")
        and (state.status ~= "error" or type(state.error) == "string")
        and (state.poseCertainty == "known" or state.poseCertainty == "uncertain")
        and poseValid(state.pose)
        and routeValid(state.route, state.pose)
        and floorLandingsValid(state.floorLandings, state.route)
        and landingChainValid(state.floorLandings or {})
        and (state.routeStack == nil or ActionStack.validate(state.routeStack))
        and configSnapshotValid(state.configSnapshot)
        and pendingActionValid(state.pendingAction)
        and MiningCursor.validate(state.progress)
        and workUnitValid(state.progress)
        and (state.resumeCheckpoint == nil
            or resumeCheckpointValid(state.resumeCheckpoint, state.progress))
        and serviceValid(state.service, state.progress)
        and lightingValid(state.lighting)
        and statisticsValid(state.statistics)
        and veinValid(state.vein, state.pose)
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

function State.validateService(service, progress)
    return serviceValid(service, progress)
end

function State.validateVein(vein, pose)
    return veinValid(vein, pose)
end

function State.validateFloorLanding(landing, route, existingLandings)
    if type(landing) ~= "table" or not integer(landing.floor) or landing.floor < 1
        or type(existingLandings) ~= "table" then return false end
    local candidate = copy(existingLandings)
    candidate[landing.floor] = copy(landing)
    return floorLandingsValid(candidate, route) and landingChainValid(candidate)
end

function State.new(configSnapshot, pose, route, runId)
    local initialProgress = assert(MiningCursor.withWorkUnit(MiningCursor.initial(), pose, configSnapshot))
    local state = {
        schemaVersion = SCHEMA_VERSION,
        runId = runId,
        status = "mining",
        poseCertainty = "known",
        pose = copy(pose),
        route = copy(route),
        floorLandings = {},
        routeStack = { records = {} },
        vein = nil,
        lighting = { placed = {} },
        progress = initialProgress,
        resumeCheckpoint = { pose = copy(pose), progress = copy(initialProgress) },
        pendingAction = nil,
        configSnapshot = copy(configSnapshot),
    }
    if not valid(state) then return nil, "INVALID_STATE" end
    return state
end

function State.validateLighting(lighting)
    return lightingValid(lighting)
end

function State.validateStatistics(statistics)
    return statisticsValid(statistics)
end

function State.save(state, path, fsApi, textutilsApi)
    if not valid(state) then return false, "STATE_INVALID" end
    local tempPath, backupPath = path .. ".tmp", path .. ".bak"
    local encoded = serialize(state, textutilsApi)
    if not encoded or not writeFile(tempPath, encoded, fsApi) then
        return false, "STATE_WRITE_FAILED"
    end
    local checkRaw = readFile(tempPath, fsApi)
    local checked = checkRaw and decode(checkRaw, textutilsApi) or nil
    if not checked then
        return false, "STATE_TEMP_INVALID"
    end
    if not valid(checked) then return false, "STATE_TEMP_INVALID" end
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
    if state and not valid(state) then state = nil end
    local fromBackup = false
    if not state then
        local backupRaw = readFile(path .. ".bak", fsApi)
        state = backupRaw and decode(backupRaw, textutilsApi) or nil
        if state and not valid(state) then state = nil end
        fromBackup = state ~= nil
    end
    if not state then
        local tempRaw = readFile(path .. ".tmp", fsApi)
        local tempState = tempRaw and decode(tempRaw, textutilsApi) or nil
        if tempState and valid(tempState) then
            state = tempState
            local activeRaw = readFile(path, fsApi)
            local activeState = activeRaw and decode(activeRaw, textutilsApi) or nil
            if activeState and valid(activeState) then
                -- Keep the displaced valid snapshot as the backup before
                -- promoting the fully validated interrupted commit.
                if fsApi.exists(path .. ".bak") then fsApi.delete(path .. ".bak") end
                fsApi.move(path, path .. ".bak")
            elseif activeRaw then
                fsApi.delete(path)
            end
            if not fsApi.exists(path) then fsApi.move(path .. ".tmp", path) end
            if fsApi.exists(path) then
                fromBackup = false
                reason = nil
            else
                state = nil
            end
        end
    end
    if not state then
        if reason == "MISSING" and not fsApi.exists(path .. ".bak")
            and not fsApi.exists(path .. ".tmp") then
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
