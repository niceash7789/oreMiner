-- In-memory graph of movement edges the turtle has successfully traversed.
-- Every recorded edge is reversible because the move already cleared its cell.
local KnownRoute = {}

local function key(pose)
    if type(pose) ~= "table"
        or type(pose.x) ~= "number"
        or type(pose.y) ~= "number"
        or type(pose.z) ~= "number" then
        return nil
    end
    return pose.x .. "," .. pose.y .. "," .. pose.z
end

local function adjacent(fromPose, toPose)
    return math.abs(fromPose.x - toPose.x)
        + math.abs(fromPose.y - toPose.y)
        + math.abs(fromPose.z - toPose.z) == 1
end

function KnownRoute.new(home)
    local homeKey = key(home)
    if not homeKey then
        return nil, "INVALID_HOME_POSE"
    end

    return {
        home = homeKey,
        edges = { [homeKey] = {} },
    }
end

local function addEdge(route, fromKey, toKey)
    route.edges[fromKey] = route.edges[fromKey] or {}
    route.edges[toKey] = route.edges[toKey] or {}
    route.edges[fromKey][toKey] = true
    route.edges[toKey][fromKey] = true
end

function KnownRoute.recordMove(route, fromPose, toPose)
    local fromKey = key(fromPose)
    local toKey = key(toPose)
    if not route or not fromKey or not toKey or not adjacent(fromPose, toPose) then
        return false, "INVALID_ROUTE_MOVE"
    end
    addEdge(route, fromKey, toKey)
    return true
end

function KnownRoute.hasEdge(route, fromPose, toPose)
    local fromKey = key(fromPose)
    local toKey = key(toPose)
    return route ~= nil and fromKey ~= nil and toKey ~= nil
        and route.edges[fromKey] ~= nil and route.edges[fromKey][toKey] == true
end

local function distances(route, startKey, extraFrom, extraTo)
    if not route.edges[startKey] and startKey ~= extraTo then
        return nil
    end

    local seen = { [startKey] = 0 }
    local queue = { startKey }
    local head = 1
    while head <= #queue do
        local current = queue[head]
        head = head + 1
        for neighbor in pairs(route.edges[current] or {}) do
            if seen[neighbor] == nil then
                seen[neighbor] = seen[current] + 1
                queue[#queue + 1] = neighbor
            end
        end
        if extraFrom == current and seen[extraTo] == nil then
            seen[extraTo] = seen[current] + 1
            queue[#queue + 1] = extraTo
        elseif extraTo == current and seen[extraFrom] == nil then
            seen[extraFrom] = seen[current] + 1
            queue[#queue + 1] = extraFrom
        end
    end
    return seen
end

-- Cost after a proposed successful move. The proposed edge is treated as
-- traversable in either direction; all other edges must already be recorded.
function KnownRoute.projectedReturnCost(route, currentPose, proposedPose)
    local currentKey = key(currentPose)
    local proposedKey = key(proposedPose)
    if not route or not currentKey or not proposedKey or not adjacent(currentPose, proposedPose) then
        return nil, "INVALID_ROUTE_POSE"
    end

    local currentDistances = distances(route, currentKey)
    if not currentDistances or currentDistances[route.home] == nil then
        return nil, "UNKNOWN_CURRENT_ROUTE"
    end

    local projectedDistances = distances(route, proposedKey, currentKey, proposedKey)
    if not projectedDistances or projectedDistances[route.home] == nil then
        return nil, "UNKNOWN_RETURN_ROUTE"
    end
    return projectedDistances[route.home], "KNOWN_ROUTE_COST"
end

return KnownRoute
