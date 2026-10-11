-- Coordinates durable snapshots without exposing the live state machine to storage details.
local Checkpoint = {}
local Session = {}
Session.__index = Session
local StateCodec = require("src.persistence.state")
local ActionStack = require("src.navigation.action_stack")

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local function sameCursor(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then return false end
    for _, field in ipairs({ "workDomain", "workUnitId", "floor", "stairSegment",
        "stairStep", "branchPair", "side", "phase", "offset", "mainOffset", "nextAction" }) do
        if left[field] ~= right[field] then return false end
    end
    return true
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
    if self.statisticsProvider then
        local ok, values = pcall(self.statisticsProvider)
        if ok and self.stateApi.validateStatistics(values) then
            self.state.statistics = copy(values)
        end
    end
end

function Session.setStatisticsProvider(self, provider)
    if provider ~= nil and type(provider) ~= "function" then return false end
    self.statisticsProvider = provider
    return true
end

function Session.statistics(self)
    return copy(self.state.statistics or {})
end

function Session.save(self, pose, route, configSnapshot)
    self:snapshot(pose, route, configSnapshot)
    return self.stateApi.save(self.state, self.path, self.fsApi, self.textutilsApi)
end

function Session.resumeCheckpoint(self)
    return copy(self.state.resumeCheckpoint)
end

function Session.service(self)
    return copy(self.state.service)
end

function Session.vein(self)
    return copy(self.state.vein)
end

function Session.lighting(self)
    return copy(self.state.lighting or { placed = {} })
end

function Session.hasTorchPlacement(self, key)
    return type(key) == "string" and self.state.lighting ~= nil
        and self.state.lighting.placed[key] == true
end

function Session.recordTorchPlacement(self, key, pose, route, configSnapshot)
    if type(key) ~= "string" or #key == 0 then return false, "INVALID_TORCH_KEY" end
    local lighting = copy(self.state.lighting or { placed = {} })
    lighting.placed[key] = true
    if not self.stateApi.validateLighting(lighting) then return false, "INVALID_LIGHTING_STATE" end
    local previous = self.state.lighting
    self.state.lighting = lighting
    local ok, code = self:save(pose, route, configSnapshot)
    if not ok then self.state.lighting = previous end
    return ok, code
end

function Session.setVein(self, vein, pose, route, configSnapshot)
    local domainVein = copy(vein)
    if type(domainVein) == "table" then domainVein.workDomain = "ore" end
    if not self.stateApi.validateVein(domainVein, pose) then
        return false, "INVALID_VEIN_STATE"
    end
    local previous = self.state.vein
    self.state.vein = domainVein
    local ok, code = self:save(pose, route, configSnapshot)
    if not ok then self.state.vein = previous end
    return ok, code
end

function Session.setService(self, service, pose, route, configSnapshot)
    local framedService = copy(service)
    if type(framedService) == "table" then framedService.workDomain = "service" end
    if type(framedService) == "table"
        and sameCursor(framedService.resumeProgress, self.state.progress) then
        -- Service resumes the already committed mining unit, including its
        -- durable origin/frame/bounds metadata.
        framedService.resumeProgress = copy(self.state.progress)
    end
    if not self.stateApi.validateService(framedService, self.state.progress) then
        return false, "INVALID_SERVICE_STATE"
    end
    local previous = self.state.service
    self.state.service = framedService
    local ok, code = self:save(pose, route, configSnapshot)
    if not ok then self.state.service = previous end
    return ok, code
end

function Session.setProgress(self, progress, pose, route, configSnapshot)
    if not self.stateApi.validateProgress(progress) then
        return false, "INVALID_MINING_CURSOR"
    end
    local framedProgress, frameCode = require("src.mining.cursor").withWorkUnit(
        progress, pose, configSnapshot)
    if not framedProgress then return false, frameCode end
    local previous = self.state.progress
    local previousCheckpoint = self.state.resumeCheckpoint
    self.state.progress = copy(framedProgress)
    self.state.resumeCheckpoint = { pose = copy(pose), progress = copy(framedProgress) }
    local ok, code = self:save(pose, route, configSnapshot)
    if not ok then
        self.state.progress = previous
        self.state.resumeCheckpoint = previousCheckpoint
    end
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

function Session.routeStack(self)
    return copy(self.state.routeStack or { records = {} })
end

function Session.recordRouteAction(self, action, pose, route, configSnapshot)
    local previous = copy(self.state.routeStack or { records = {} })
    local candidate = copy(previous)
    local outcome = ActionStack.record(candidate, action)
    if outcome.ok ~= true then return false, outcome.code end
    self.state.routeStack = candidate
    local ok, code = self:save(pose, route, configSnapshot)
    if not ok then self.state.routeStack = previous end
    return ok, code
end

-- Persist a reversible route edge together with its pending physical intent.
-- Recovery will still report POSITION_UNCERTAIN if power is lost after this write.
function Session.beginRouteAction(self, action, kind, direction, pose, route, configSnapshot)
    if (kind ~= "move" and kind ~= "turn") or type(direction) ~= "string" then
        return false, "INVALID_ROUTE_ACTION"
    end
    local previousStack = copy(self.state.routeStack or { records = {} })
    local candidate = copy(previousStack)
    local recorded = ActionStack.record(candidate, action)
    if recorded.ok ~= true then return false, recorded.code end
    local previousAction = self.state.pendingAction
    self.state.routeStack = candidate
    self.state.pendingAction = { kind = kind, direction = direction }
    local ok, code = self:save(pose, route, configSnapshot)
    if not ok then
        self.state.routeStack = previousStack
        self.state.pendingAction = previousAction
    end
    return ok, code
end

-- Cancel a route action only after the physical API explicitly reports
-- failure. A failed save retains pending intent and the provisional edge.
function Session.cancelRouteAction(self, expectedAction, pose, route, configSnapshot)
    local previousStack = copy(self.state.routeStack or { records = {} })
    local candidate = copy(previousStack)
    local top = candidate.records[#candidate.records]
    if not top or top.action ~= expectedAction or self.state.pendingAction == nil then
        return false, "ROUTE_STACK_MISMATCH"
    end
    candidate.records[#candidate.records] = nil
    local previousAction = self.state.pendingAction
    self.state.routeStack = candidate
    self.state.pendingAction = nil
    local ok, code = self:save(pose, route, configSnapshot)
    if not ok then
        self.state.routeStack = previousStack
        self.state.pendingAction = previousAction
    end
    return ok, code
end

function Session.unwindRouteStack(self, applyInverse, pose, route, configSnapshot)
    if type(applyInverse) ~= "function" then return false, "INVALID_ROUTE_UNWIND" end
    local stack = self.state.routeStack or { records = {} }
    local outcome = ActionStack.unwindPersisted(stack, applyInverse, function(candidate)
        local previous = self.state.routeStack
        self.state.routeStack = copy(candidate)
        local saved = self:save(pose, route, configSnapshot)
        if not saved then self.state.routeStack = previous end
        return saved == true
    end)
    if not outcome.ok then return false, outcome.code end
    self.state.routeStack = stack
    return true, "ROUTE_UNWOUND"
end

function Session.commitRouteInverse(self, expectedInverse, pose, route, configSnapshot)
    local stack = self.state.routeStack or { records = {} }
    local top = stack.records[#stack.records]
    if not top or top.inverse ~= expectedInverse then return false, "ROUTE_STACK_MISMATCH" end
    local previous = copy(stack)
    stack.records[#stack.records] = nil
    local ok, code = self:save(pose, route, configSnapshot)
    if not ok then self.state.routeStack = previous end
    return ok, code
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

-- Commit an inverse move/turn and pop its route record in the same snapshot.
function Session.commitRouteAction(self, expectedInverse, pose, route, configSnapshot)
    local previousStack = copy(self.state.routeStack or { records = {} })
    local candidate = copy(previousStack)
    local top = candidate.records[#candidate.records]
    if not top or top.inverse ~= expectedInverse then return false, "ROUTE_STACK_MISMATCH" end
    candidate.records[#candidate.records] = nil
    local previousAction = self.state.pendingAction
    self.state.routeStack = candidate
    self.state.pendingAction = nil
    local ok, code = self:save(pose, route, configSnapshot)
    if not ok then
        self.state.routeStack = previousStack
        self.state.pendingAction = previousAction
    end
    return ok, code
end

-- Commit a successful vein edge and its matching DFS state in one snapshot.
-- The pending intent remains durable until this write succeeds, so a crash
-- between the world action and this snapshot is still reported uncertain.
function Session.commitVeinAction(self, pose, route, configSnapshot, vein)
    local domainVein = copy(vein)
    if type(domainVein) == "table" then domainVein.workDomain = "ore" end
    local clearingAtCheckpoint = domainVein == nil and self.state.vein ~= nil
        and self.state.vein.checkpoint.x == pose.x
        and self.state.vein.checkpoint.y == pose.y
        and self.state.vein.checkpoint.z == pose.z
        and self.state.vein.checkpoint.facing == pose.facing
    if domainVein == nil and not clearingAtCheckpoint then
        return false, "INVALID_VEIN_STATE"
    end
    if domainVein ~= nil and not self.stateApi.validateVein(domainVein, pose) then
        return false, "INVALID_VEIN_STATE"
    end
    local previousVein = self.state.vein
    local previousPending = self.state.pendingAction
    self.state.vein = domainVein
    self.state.pendingAction = nil
    local ok, code = self:save(pose, route, configSnapshot)
    if not ok then
        self.state.vein = previousVein
        self.state.pendingAction = previousPending
    end
    return ok, code
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

function Session.markPaused(self, pose, route, configSnapshot)
    local previous = self.state.status
    self.state.status = "paused"
    local ok, code = self:save(pose, route, configSnapshot)
    if not ok then self.state.status = previous end
    return ok, code
end

function Session.markMining(self, pose, route, configSnapshot)
    local previous = self.state.status
    self.state.status = "mining"
    local ok, code = self:save(pose, route, configSnapshot)
    if not ok then self.state.status = previous end
    return ok, code
end

function Session.markComplete(self, pose, route, configSnapshot)
    self.state.status = "complete"
    if type(self.state.progress) == "table" and self.state.progress.origin ~= nil then
        self.state.progress.completionStatus = "complete"
        if self.state.resumeCheckpoint and self.state.resumeCheckpoint.progress then
            self.state.resumeCheckpoint.progress.completionStatus = "complete"
        end
    end
    return self:save(pose, route, configSnapshot)
end

function Session.status(self)
    return self.state.status
end

function Session.snapshotState(self)
    return copy(self.state)
end

return Checkpoint
