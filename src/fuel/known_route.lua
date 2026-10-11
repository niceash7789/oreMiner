-- In-memory graph of movement edges the turtle has successfully traversed.
-- Every recorded edge is reversible because the move already cleared its cell.
local KnownRoute = {}
local MAX_TRAIL_NODES = 100000

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
        trail = { homeKey },
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
    local trail = route.trail
    local previousIndex
    if trail ~= nil then
        if type(trail) ~= "table" or trail[#trail] ~= fromKey then
            return false, "ROUTE_TRAIL_POSE_MISMATCH"
        end
        for index = #trail - 1, 1, -1 do
            if trail[index] == toKey then
                previousIndex = index
                break
            end
        end
        if not previousIndex and #trail >= MAX_TRAIL_NODES then
            return false, "ROUTE_TRAIL_LIMIT"
        end
    end
    addEdge(route, fromKey, toKey)
    if trail ~= nil then
        if previousIndex then
            for index = #trail, previousIndex + 1, -1 do trail[index] = nil end
        else
            trail[#trail + 1] = toKey
        end
    end
    return true
end

-- A compact, loop-erased sequence of individually committed cells from home
-- to the current pose. Legacy snapshots without a trail still use the graph.
function KnownRoute.trailHome(route, pose)
    if type(route) ~= "table" or route.trail == nil then return nil, "NO_ROUTE_TRAIL" end
    local trail = route.trail
    if type(trail) ~= "table" or #trail < 1 or #trail > MAX_TRAIL_NODES
        or trail[1] ~= route.home or trail[#trail] ~= key(pose) then
        return nil, "ROUTE_TRAIL_INVALID"
    end
    local path = {}
    for index = #trail, 2, -1 do
        local fromKey, toKey = trail[index], trail[index - 1]
        if type(route.edges[fromKey]) ~= "table"
            or route.edges[fromKey][toKey] ~= true then
            return nil, "ROUTE_TRAIL_INVALID"
        end
        local x, y, z = toKey:match("^(-?%d+),(-?%d+),(-?%d+)$")
        if not x then return nil, "ROUTE_TRAIL_INVALID" end
        path[#path + 1] = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
    end
    return path, "ROUTE_TRAIL_COST"
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
    if route.trail ~= nil then
        local path, reason = KnownRoute.trailHome(route, currentPose)
        if not path then return nil, reason end
        for index = #route.trail - 1, 1, -1 do
            if route.trail[index] == proposedKey then
                return index - 1, "KNOWN_ROUTE_COST"
            end
        end
        if #route.trail >= MAX_TRAIL_NODES then return nil, "ROUTE_TRAIL_LIMIT" end
        return #route.trail, "KNOWN_ROUTE_COST"
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

-- Return the exact shortest cost from a committed state pose to home. The
-- recorded route graph is authoritative for every valid phase; in particular,
-- active vein breadcrumbs must correspond to edges on this graph.
function KnownRoute.costHome(state)
    if type(state) ~= "table" or type(state.pose) ~= "table"
        or type(state.route) ~= "table" then
        return nil, "INVALID_ROUTE_STATE"
    end
    if state.poseCertainty ~= nil and state.poseCertainty ~= "known" then
        return nil, "POSITION_UNCERTAIN"
    end
    if state.pendingAction ~= nil then
        return nil, "POSITION_UNCERTAIN"
    end
    local homeKey = key({ x = 0, y = 0, z = 0 })
    if state.route.home ~= homeKey then return nil, "INVALID_HOME_ROUTE" end
    local currentKey = key(state.pose)
    if not currentKey then return nil, "INVALID_ROUTE_POSE" end
    local trailCost
    if state.route.trail ~= nil then
        local trail, trailReason = KnownRoute.trailHome(state.route, state.pose)
        if not trail then return nil, trailReason end
        trailCost = #trail
    end
    local vein = state.vein
    if vein ~= nil then
        if type(vein) ~= "table" or type(vein.checkpoint) ~= "table"
            or type(vein.route) ~= "table" or type(vein.visited) ~= "table"
            or vein.stage == "entering" then
            return nil, "UNKNOWN_VEIN_RETURN_ROUTE"
        end
        if vein.stage ~= "active" and vein.stage ~= "unwinding" then
            return nil, "UNKNOWN_VEIN_RETURN_ROUTE"
        end
        local cursor = state.pose
        local edgeCount = 0
        for index = #vein.route, 1, -1 do
            local breadcrumb = vein.route[index]
            if type(breadcrumb) ~= "table" then return nil, "UNKNOWN_VEIN_RETURN_ROUTE" end
            local target = { x = cursor.x, y = cursor.y, z = cursor.z, facing = cursor.facing }
            if breadcrumb.inverse == "up" then target.y = target.y + 1
            elseif breadcrumb.inverse == "down" then target.y = target.y - 1
            elseif breadcrumb.inverse == "back" then
                target.facing = breadcrumb.facing
                if breadcrumb.facing == 0 then target.z = target.z + 1
                elseif breadcrumb.facing == 1 then target.x = target.x - 1
                elseif breadcrumb.facing == 2 then target.z = target.z - 1
                elseif breadcrumb.facing == 3 then target.x = target.x + 1
                else return nil, "UNKNOWN_VEIN_RETURN_ROUTE" end
            else
                return nil, "UNKNOWN_VEIN_RETURN_ROUTE"
            end
            local cursorKey = key(cursor)
            local targetKey = key(target)
            if not state.route.edges[cursorKey] or not state.route.edges[cursorKey][targetKey] then
                return nil, "UNKNOWN_VEIN_RETURN_ROUTE"
            end
            edgeCount = edgeCount + 1
            cursor = target
        end
        if edgeCount ~= #vein.route or cursor.x ~= vein.checkpoint.x
            or cursor.y ~= vein.checkpoint.y or cursor.z ~= vein.checkpoint.z then
            return nil, "UNKNOWN_VEIN_RETURN_ROUTE"
        end
    end

    -- Measure from the committed physical pose. Breadcrumb validation proves
    -- that the active excursion can unwind, while the recorded graph already
    -- contains those edges and therefore prices that retrace exactly once.
    local routeKey = currentKey
    local reachable = distances(state.route, routeKey)
    local cost = reachable and reachable[homeKey]
    if cost == nil then return nil, "UNKNOWN_RETURN_ROUTE" end
    -- The route graph already includes committed vein edges; adding their
    -- breadcrumb count again would double-charge the same retrace.
    return trailCost or cost, "KNOWN_ROUTE_COST"
end

return KnownRoute
