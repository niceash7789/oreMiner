local VeinTraversal = {}

local MAX_BLOCKS = 64
local MAX_DEPTH = 8

local function copyFrames(frames)
    local result = {}
    for index, frame in ipairs(frames) do
        result[index] = { next = frame.next, rotateOnReturn = frame.rotateOnReturn }
    end
    return result
end

local function copyRoute(route)
    local result = {}
    for index, breadcrumb in ipairs(route) do
        result[index] = { inverse = breadcrumb.inverse, facing = breadcrumb.facing }
    end
    return result
end

function VeinTraversal.unwindSaved(vein, ops, saveState)
    if type(vein) ~= "table" or type(ops) ~= "table" or type(ops.pose) ~= "function"
        or type(ops.move) ~= "function" or type(ops.turn) ~= "function"
        or type(saveState) ~= "function" then
        return { ok = false, code = "VEIN_RESUME_INVALID", blocks = 0 }
    end
    local route = copyRoute(vein.route)
    local frontier = copyFrames(vein.frontier)
    local visited = {}
    for coordinate, seen in pairs(vein.visited) do
        if seen then visited[coordinate] = true end
    end
    local blocks = vein.blocks
    if #frontier > #route then frontier[#frontier] = nil end
    local function persist(stage)
        local visitedSnapshot = {}
        for coordinate, seen in pairs(visited) do
            if seen then visitedSnapshot[coordinate] = true end
        end
        local snapshot = {
            stage = stage,
            checkpoint = { x = vein.checkpoint.x, y = vein.checkpoint.y,
                z = vein.checkpoint.z, facing = vein.checkpoint.facing },
            visited = visitedSnapshot,
            frontier = copyFrames(frontier),
            route = copyRoute(route),
            blocks = blocks,
        }
        return saveState(snapshot) == true
    end
    local function samePose(left, right)
        return left.x == right.x and left.y == right.y and left.z == right.z
            and left.facing == right.facing
    end
    if not persist("unwinding") then
        return { ok = false, code = "VEIN_STATE_WRITE_FAILED", blocks = blocks }
    end
    while #route > 0 do
        local breadcrumb = route[#route]
        local turns = (breadcrumb.facing - ops.pose().facing) % 4
        for _ = 1, turns do
            if ops.turn("right") ~= true then
                return { ok = false, code = "VEIN_TURN_FAILED", blocks = blocks }
            end
        end
        if ops.move(breadcrumb.inverse) ~= true then
            return { ok = false, code = "VEIN_RETURN_BLOCKED", blocks = blocks }
        end
        route[#route] = nil
        while #frontier > #route do frontier[#frontier] = nil end
        if #route > 0 and not persist("unwinding") then
            return { ok = false, code = "VEIN_STATE_WRITE_FAILED", blocks = blocks }
        end
    end
    if not samePose(ops.pose(), vein.checkpoint) then
        return { ok = false, code = "VEIN_CHECKPOINT_MISMATCH", blocks = blocks }
    end
    if saveState(nil) ~= true then
        return { ok = false, code = "VEIN_STATE_WRITE_FAILED", blocks = blocks }
    end
    return { ok = true, code = "VEIN_CHECKPOINT_RESTORED", blocks = blocks }
end

local function key(pose)
    return pose.x .. "," .. pose.y .. "," .. pose.z
end

local function samePose(a, b)
    return a.x == b.x and a.y == b.y and a.z == b.z and a.facing == b.facing
end

local function unwindResult(unwind, reason, blocks)
    local ok, code = unwind()
    return { ok = ok, code = ok and reason or code, blocks = blocks }
end

-- Callbacks must report literal true for successful physical actions.
-- Optional beforeDiscover returns true to request an immediate checkpoint unwind.
function VeinTraversal.run(checkpoint, ops, seedInverse, qualifies, onMined, saveState)
    if type(qualifies) ~= "function" then
        return { ok = false, code = "VEIN_INVALID_QUALIFIER", blocks = 0 }
    end
    local visited = { [key(ops.pose())] = true }
    local route = { { inverse = seedInverse, facing = ops.pose().facing } }
    local frontier = { { next = 1, rotateOnReturn = false } }
    local blocks = 1
    local capReached = false
    local unwindRequested = false

    local function persist(stage)
        if type(saveState) ~= "function" then return true end
        local snapshot = {
            stage = stage,
            checkpoint = {
                x = checkpoint.x, y = checkpoint.y, z = checkpoint.z,
                facing = checkpoint.facing,
            },
            visited = {},
            frontier = copyFrames(frontier),
            route = copyRoute(route),
            blocks = blocks,
        }
        for coordinate, seen in pairs(visited) do
            if seen then snapshot.visited[coordinate] = true end
        end
        return saveState(snapshot) == true
    end

    local function restoreHeading(heading)
        local turns = (heading - ops.pose().facing) % 4
        for _ = 1, turns do
            if type(ops.turn) == "function" then
                if ops.turn("right") ~= true then return false end
            elseif ops.turnRight() ~= true then
                return false
            end
        end
        return true
    end

    local function reverseLast()
        local breadcrumb = route[#route]
        if not breadcrumb or not restoreHeading(breadcrumb.facing)
            or ops.move(breadcrumb.inverse) ~= true then
            return false
        end
        route[#route] = nil
        if #route > 0 and not persist("unwinding") then return false end
        return true
    end

    local function unwind()
        if #route > 0 and not persist("unwinding") then
            return false, "VEIN_STATE_WRITE_FAILED"
        end
        while #route > 0 do
            if not reverseLast() then
                return false, "VEIN_RETURN_BLOCKED"
            end
        end
        if not samePose(ops.pose(), checkpoint) then
            return false, "VEIN_CHECKPOINT_MISMATCH"
        end
        return true
    end

    if not persist("active") then
        return { ok = false, code = "VEIN_STATE_WRITE_FAILED", blocks = blocks }
    end

    while #frontier > 0 do
        local frame = frontier[#frontier]
        local direction
        if frame.next <= 4 then
            direction = "forward"
        elseif frame.next == 5 then
            direction = "up"
        elseif frame.next == 6 then
            direction = "down"
        else
            frontier[#frontier] = nil
            if #frontier > 0 then
                if not reverseLast() then
                    return { ok = false, code = "VEIN_RETURN_BLOCKED", blocks = blocks }
                end
                if frame.rotateOnReturn and (type(ops.turn) == "function"
                    and ops.turn("right") ~= true or type(ops.turn) ~= "function"
                    and ops.turnRight() ~= true) then
                    return { ok = false, code = "VEIN_TURN_FAILED", blocks = blocks }
                end
                if frame.rotateOnReturn and not persist("active") then
                    return { ok = false, code = "VEIN_STATE_WRITE_FAILED", blocks = blocks }
                end
            end
            direction = nil
        end

        if direction then
            frame.next = frame.next + 1
            local enteredChild = false
            if type(ops.beforeDiscover) == "function" and ops.beforeDiscover() == true then
                return unwindResult(unwind, "INVENTORY_RETURN", blocks)
            end
            if direction == "forward" then
                local found, block = ops.inspect(direction)
                if found == true and qualifies(block) == true then
                    local target = ops.project(direction)
                    local depth = #route + 1
                    if not visited[key(target)] then
                        local radius = math.abs(target.x - checkpoint.x)
                            + math.abs(target.y - checkpoint.y)
                            + math.abs(target.z - checkpoint.z)
                        if depth > MAX_DEPTH or radius > MAX_DEPTH or blocks >= MAX_BLOCKS then
                            capReached = true
                        elseif type(ops.canContinue) == "function" and ops.canContinue(target) ~= true then
                            return unwindResult(unwind, "VEIN_FUEL_RETURN", blocks)
                        elseif ops.inventoryPressure() == true then
                            return unwindResult(unwind, "INVENTORY_RETURN", blocks)
                        elseif ops.dig(direction) ~= true then
                            local ok, code = unwind()
                            return { ok = false, code = ok and "VEIN_DIG_FAILED" or code, blocks = blocks }
                        elseif ops.move(direction) ~= true then
                            return { ok = false, code = "VEIN_MOVE_FAILED", blocks = blocks }
                        else
                            if type(onMined) == "function" then pcall(onMined, block) end
                            visited[key(ops.pose())] = true
                            route[#route + 1] = { inverse = "back", facing = ops.pose().facing }
                            blocks = blocks + 1
                            frontier[#frontier + 1] = { next = 1, rotateOnReturn = true }
                            if not persist("active") then
                                return { ok = false, code = "VEIN_STATE_WRITE_FAILED", blocks = blocks }
                            end
                            enteredChild = true
                        end
                    end
                end
                if unwindRequested then
                    return { ok = false, code = "VEIN_DISCOVERY_AFTER_UNWIND", blocks = blocks }
                end
                if not enteredChild and (type(ops.turn) == "function"
                    and ops.turn("right") ~= true or type(ops.turn) ~= "function"
                    and ops.turnRight() ~= true) then
                    local ok, code = unwind()
                    return { ok = false, code = ok and "VEIN_TURN_FAILED" or code, blocks = blocks }
                end
                if not enteredChild and not persist("active") then
                    return { ok = false, code = "VEIN_STATE_WRITE_FAILED", blocks = blocks }
                end
            else
                local found, block = ops.inspect(direction)
                if found == true and qualifies(block) == true then
                    local target = ops.project(direction)
                    local depth = #route + 1
                    if not visited[key(target)] then
                        local radius = math.abs(target.x - checkpoint.x)
                            + math.abs(target.y - checkpoint.y)
                            + math.abs(target.z - checkpoint.z)
                        if depth > MAX_DEPTH or radius > MAX_DEPTH or blocks >= MAX_BLOCKS then
                            capReached = true
                        elseif type(ops.canContinue) == "function" and ops.canContinue(target) ~= true then
                            return unwindResult(unwind, "VEIN_FUEL_RETURN", blocks)
                        elseif ops.inventoryPressure() == true then
                            return unwindResult(unwind, "INVENTORY_RETURN", blocks)
                        elseif ops.dig(direction) ~= true then
                            local ok, code = unwind()
                            return { ok = false, code = ok and "VEIN_DIG_FAILED" or code, blocks = blocks }
                        elseif ops.move(direction) ~= true then
                            return { ok = false, code = "VEIN_MOVE_FAILED", blocks = blocks }
                        else
                            if type(onMined) == "function" then pcall(onMined, block) end
                            visited[key(ops.pose())] = true
                            route[#route + 1] = {
                                inverse = direction == "up" and "down" or "up",
                                facing = ops.pose().facing,
                            }
                            blocks = blocks + 1
                            frontier[#frontier + 1] = { next = 1, rotateOnReturn = false }
                            if not persist("active") then
                                return { ok = false, code = "VEIN_STATE_WRITE_FAILED", blocks = blocks }
                            end
                            enteredChild = true
                        end
                    end
                end
                if unwindRequested then
                    return { ok = false, code = "VEIN_DISCOVERY_AFTER_UNWIND", blocks = blocks }
                end
                if not enteredChild and not persist("active") then
                    return { ok = false, code = "VEIN_STATE_WRITE_FAILED", blocks = blocks }
                end
            end
        end
    end

    local ok, code = unwind()
    if ok and type(saveState) == "function" and saveState(nil) ~= true then
        return { ok = false, code = "VEIN_STATE_WRITE_FAILED", blocks = blocks }
    end
    if ok and capReached and type(ops.reportCap) == "function" then
        pcall(ops.reportCap, blocks, MAX_BLOCKS, MAX_DEPTH)
    end
    return { ok = ok, code = code or (capReached and "VEIN_CAP_REACHED" or "VEIN_COMPLETE"), blocks = blocks }
end

return VeinTraversal
