local VeinTraversal = {}

local MAX_BLOCKS = 64
local MAX_DEPTH = 8

local function key(pose)
    return pose.x .. "," .. pose.y .. "," .. pose.z
end

local function samePose(a, b)
    return a.x == b.x and a.y == b.y and a.z == b.z and a.facing == b.facing
end

-- Callbacks must report literal true for successful physical actions.
-- Optional beforeDiscover returns true to request an immediate checkpoint unwind.
function VeinTraversal.run(checkpoint, ops, seedInverse, qualifies, onMined)
    if type(qualifies) ~= "function" then
        return { ok = false, code = "VEIN_INVALID_QUALIFIER", blocks = 0 }
    end
    local visited = { [key(ops.pose())] = true }
    local route = { { inverse = seedInverse, facing = ops.pose().facing } }
    local frontier = { { next = 1, rotateOnReturn = false } }
    local blocks = 1
    local capReached = false
    local unwindRequested = false

    local function restoreHeading(heading)
        local turns = (heading - ops.pose().facing) % 4
        for _ = 1, turns do
            if ops.turnRight() ~= true then
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
        return true
    end

    local function unwind()
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
                if frame.rotateOnReturn and ops.turnRight() ~= true then
                    return { ok = false, code = "VEIN_TURN_FAILED", blocks = blocks }
                end
            end
            direction = nil
        end

        if direction then
            frame.next = frame.next + 1
            local enteredChild = false
            if type(ops.beforeDiscover) == "function" and ops.beforeDiscover() == true then
                unwindRequested = true
                local ok, code = unwind()
                return { ok = ok, code = ok and "INVENTORY_RETURN" or code, blocks = blocks }
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
                        elseif ops.inventoryPressure() == true then
                            unwindRequested = true
                            local ok, code = unwind()
                            return { ok = ok, code = ok and "INVENTORY_RETURN" or code, blocks = blocks }
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
                            enteredChild = true
                        end
                    end
                end
                if unwindRequested then
                    return { ok = false, code = "VEIN_DISCOVERY_AFTER_UNWIND", blocks = blocks }
                end
                if not enteredChild and ops.turnRight() ~= true then
                    local ok, code = unwind()
                    return { ok = false, code = ok and "VEIN_TURN_FAILED" or code, blocks = blocks }
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
                        elseif ops.inventoryPressure() == true then
                            unwindRequested = true
                            local ok, code = unwind()
                            return { ok = ok, code = ok and "INVENTORY_RETURN" or code, blocks = blocks }
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
                            enteredChild = true
                        end
                    end
                end
                if unwindRequested then
                    return { ok = false, code = "VEIN_DISCOVERY_AFTER_UNWIND", blocks = blocks }
                end
            end
        end
    end

    local ok, code = unwind()
    if ok and capReached and type(ops.reportCap) == "function" then
        pcall(ops.reportCap, blocks, MAX_BLOCKS, MAX_DEPTH)
    end
    return { ok = ok, code = code or (capReached and "VEIN_CAP_REACHED" or "VEIN_COMPLETE"), blocks = blocks }
end

return VeinTraversal
