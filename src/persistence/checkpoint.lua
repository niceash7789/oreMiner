-- Coordinates durable snapshots without exposing the live state machine to storage details.
local Checkpoint = {}
local Session = {}
Session.__index = Session
local StateCodec = require("src.persistence.state")

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local function wrap(state, stateApi, path, fsApi, textutilsApi)
    return setmetatable({
        state = state,
        stateApi = stateApi,
        path = path,
        fsApi = fsApi,
        textutilsApi = textutilsApi,
    }, Session)
end

function Checkpoint.create(configSnapshot, pose, route, runId, path, fsApi, textutilsApi)
    local state, code = StateCodec.new(configSnapshot, pose, route, runId)
    if not state then return nil, code end
    return wrap(state, StateCodec, path, fsApi, textutilsApi)
end

function Checkpoint.load(path, expectedConfig, fsApi, textutilsApi)
    local state, code = StateCodec.load(path, expectedConfig, fsApi, textutilsApi)
    if not state then return nil, code end
    return wrap(state, StateCodec, path, fsApi, textutilsApi), code
end

function Session.snapshot(self, pose, route, configSnapshot)
    self.state.pose = copy(pose)
    self.state.route = copy(route)
    self.state.configSnapshot = copy(configSnapshot)
end

function Session.save(self, pose, route, configSnapshot)
    self:snapshot(pose, route, configSnapshot)
    return self.stateApi.save(self.state, self.path, self.fsApi, self.textutilsApi)
end

function Session.setProgress(self, progress, pose, route, configSnapshot)
    if not self.stateApi.validateProgress(progress) then
        return false, "INVALID_MINING_CURSOR"
    end
    local previous = self.state.progress
    self.state.progress = copy(progress)
    local ok, code = self:save(pose, route, configSnapshot)
    if not ok then self.state.progress = previous end
    return ok, code
end

function Session.recordFloorLanding(self, landing, pose, route, configSnapshot)
    local landings = self.state.floorLandings or {}
    if not self.stateApi.validateFloorLanding(landing, route, landings) then
        return false, "INVALID_FLOOR_LANDING"
    end
    local previous = landings[landing.floor]
    if previous ~= nil then
        local same = previous.origin.x == landing.origin.x
            and previous.origin.y == landing.origin.y
            and previous.origin.z == landing.origin.z
            and previous.origin.facing == landing.origin.facing
            and previous.landing.x == landing.landing.x
            and previous.landing.y == landing.landing.y
            and previous.landing.z == landing.landing.z
            and previous.landing.facing == landing.landing.facing
        if not same then return false, "LANDING_CONFLICT" end
    end
    self.state.floorLandings = copy(landings)
    self.state.floorLandings[landing.floor] = copy(landing)
    local ok, code = self:save(pose, route, configSnapshot)
    if not ok then self.state.floorLandings[landing.floor] = previous end
    return ok, code
end

function Session.floorLanding(self, floor)
    if type(floor) ~= "number" or floor ~= math.floor(floor) or floor < 1 then return nil end
    local landing = self.state.floorLandings and self.state.floorLandings[floor]
    return landing and copy(landing) or nil
end

function Session.floorLandings(self)
    return copy(self.state.floorLandings or {})
end

function Session.beginAction(self, kind, direction, pose, route, configSnapshot)
    self.state.pendingAction = { kind = kind, direction = direction }
    local ok, code = self:save(pose, route, configSnapshot)
    if not ok then self.state.pendingAction = nil end
    return ok, code
end

function Session.commitAction(self, pose, route, configSnapshot)
    self.state.pendingAction = nil
    return self:save(pose, route, configSnapshot)
end

function Session.cancelAction(self, pose, route, configSnapshot)
    self.state.pendingAction = nil
    return self:save(pose, route, configSnapshot)
end

function Session.markFatal(self, code, pose, route, configSnapshot)
    self.state.status = "error"
    self.state.error = code
    return self:save(pose, route, configSnapshot)
end

function Session.markComplete(self, pose, route, configSnapshot)
    self.state.status = "complete"
    return self:save(pose, route, configSnapshot)
end

function Session.status(self)
    return self.state.status
end

return Checkpoint
