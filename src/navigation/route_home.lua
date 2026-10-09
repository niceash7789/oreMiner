-- Return over the shortest path made only from recorded, previously cleared
-- edges. This is a safe fallback for the active baseline until hierarchical
-- stairs/floor route builders are wired into the coordinator.
local Contracts = require("src.core.contracts")
local Pose = require("src.navigation.pose")
local KnownRoute = require("src.fuel.known_route")
local Turn = require("src.navigation.turn")
local Result = require("src.safety.result")

local RouteHome = {}
local DEFAULT_MAX_NODES = 100000

local function key(pose)
    return pose.x .. "," .. pose.y .. "," .. pose.z
end

local function parse(keyValue)
    local x, y, z = keyValue:match("^(-?%d+),(-?%d+),(-?%d+)$")
    if not x then return nil end
    return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
end

local function copyPose(pose)
    return { x = pose.x, y = pose.y, z = pose.z, facing = pose.facing }
end

local function samePosition(left, right)
    return left.x == right.x and left.y == right.y and left.z == right.z
end

local function routeKeys(route, startKey, goalKey, limit)
    if type(route) ~= "table" or type(route.edges) ~= "table"
        or type(goalKey) ~= "string" or type(route.edges[goalKey]) ~= "table"
        or type(route.edges[startKey]) ~= "table" then
        return nil, "UNKNOWN_CURRENT_ROUTE"
    end

    local queue, parent = { startKey }, { [startKey] = false }
    local head = 1
    while head <= #queue do
        local current = queue[head]
        if current == goalKey then break end
        head = head + 1
        local neighbors = {}
        for neighbor, connected in pairs(route.edges[current]) do
            if connected == true then neighbors[#neighbors + 1] = neighbor end
        end
        table.sort(neighbors)
        for _, neighbor in ipairs(neighbors) do
            if parent[neighbor] == nil then
                if #queue >= limit then return nil, "ROUTE_SEARCH_LIMIT" end
                parent[neighbor] = current
                queue[#queue + 1] = neighbor
            end
        end
    end
    if parent[goalKey] == nil then return nil, "UNKNOWN_RETURN_ROUTE" end

    local reversed = {}
    local cursor = goalKey
    while cursor ~= startKey do
        reversed[#reversed + 1] = cursor
        cursor = parent[cursor]
    end
    local path = {}
    for index = #reversed, 1, -1 do path[#path + 1] = reversed[index] end
    return path
end

function RouteHome.path(route, pose, maxNodes, targetPose)
    if not Contracts.isPose(pose) then return nil, "INVALID_POSE" end
    if maxNodes ~= nil and (type(maxNodes) ~= "number" or maxNodes < 1
        or maxNodes ~= math.floor(maxNodes)) then
        return nil, "INVALID_ROUTE_SEARCH_LIMIT"
    end
    local targetKey = Contracts.isPose(targetPose) and key(targetPose)
        or type(route) == "table" and route.home
    local keys, reason = routeKeys(route, key(pose), targetKey, maxNodes or DEFAULT_MAX_NODES)
    if not keys then return nil, reason end
    local path = {}
    for _, keyValue in ipairs(keys) do
        local position = parse(keyValue)
        if not position then return nil, "INVALID_ROUTE_COORDINATE" end
        path[#path + 1] = position
    end
    return path
end

local function facingForEdge(current, target)
    if target.x == current.x + 1 then return 1 end
    if target.x == current.x - 1 then return 3 end
    if target.z == current.z + 1 then return 2 end
    if target.z == current.z - 1 then return 0 end
    return nil
end

function RouteHome.run(options)
    if type(options) ~= "table" or not Contracts.isPose(options.pose)
        or type(options.route) ~= "table" or type(options.move) ~= "function"
        or type(options.turn) ~= "function" then
        return type(options) == "table" and options.pose or nil,
            Result.new(false, "INVALID_ROUTE_HOME_OPTIONS")
    end

    local home = parse(options.route.home or "")
    if not home then return copyPose(options.pose), Result.new(false, "INVALID_HOME_POSE") end
    local target = Contracts.isPose(options.targetPose) and options.targetPose or home
    local path, pathReason = RouteHome.path(options.route, options.pose, options.maxNodes, target)
    if not path then return copyPose(options.pose), Result.new(false, pathReason) end

    local current = copyPose(options.pose)
    for index, target in ipairs(path) do
        local nextPose
        local movement
        if target.y == current.y + 1 then
            movement = "up"
        elseif target.y == current.y - 1 then
            movement = "down"
        else
            local facing = facingForEdge(current, target)
            if facing == nil then
                return current, Result.new(false, "INVALID_RETURN_EDGE", nil, { step = index })
            end
            local turned, turnOutcome = Turn.face(current, facing, options.turn)
            current = turned
            if turnOutcome.ok ~= true then return current, turnOutcome end
            movement = "forward"
        end

        nextPose = assert(Pose.afterMove(current, movement, true))
        if not KnownRoute.hasEdge(options.route, current, nextPose) then
            return current, Result.new(false, "UNKNOWN_RETURN_EDGE", nil, { step = index })
        end
        local moved, moveOutcome = options.move(movement)
        if not Contracts.isResult(moveOutcome) or moveOutcome.ok ~= true then
            return Contracts.isPose(moved) and moved or current,
                Contracts.isResult(moveOutcome) and moveOutcome
                    or Result.new(false, "INVALID_NAVIGATION_OUTCOME", nil, { step = index })
        end
        if not Contracts.isPose(moved) or not samePosition(moved, target)
            or moved.facing ~= current.facing then
            return Contracts.isPose(moved) and moved or current,
                Result.new(false, "POSITION_ERROR", "Return movement reached an unexpected pose.", { step = index })
        end
        current = copyPose(moved)
    end

    local homeFacing = options.homeFacing
    if homeFacing ~= nil then
        local turned, turnOutcome = Turn.face(current, homeFacing, options.turn)
        current = turned
        if turnOutcome.ok ~= true then return current, turnOutcome end
    end
    if not samePosition(current, target) then
        return current, Result.new(false, "POSITION_ERROR", "Recorded route did not reach its target.")
    end
    return current, Result.new(true, samePosition(target, home) and "HOME_REACHED" or "ROUTE_TARGET_REACHED")
end

return RouteHome
