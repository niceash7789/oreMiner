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
