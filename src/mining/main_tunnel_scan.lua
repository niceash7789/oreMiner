-- Scans one already-cleared main-shaft cell and drains its candidates before
-- the coordinator advances to another route cell.
local MainTunnelScan = {}

function MainTunnelScan.scanCell(ops)
    if type(ops) ~= "table" or type(ops.scan) ~= "function"
        or type(ops.pose) ~= "function" or type(ops.candidateQueue) ~= "function"
        or type(ops.drainCandidates) ~= "function" then
        return { ok = false, code = "MAIN_SCAN_INVALID_OPS" }
    end

    if type(ops.facing) ~= "function" then
        return { ok = false, code = "MAIN_SCAN_INVALID_OPS" }
    end
    local initialFacing = ops.facing()
    local checkpoint = ops.pose()
    if type(checkpoint) ~= "table" then
        return { ok = false, code = "MAIN_SCAN_INVALID_CHECKPOINT" }
    end
    local queue = ops.candidateQueue(checkpoint)
    if type(queue) ~= "table" or type(queue.add) ~= "function"
        or type(queue.size) ~= "function" then
        return { ok = false, code = "MAIN_SCAN_QUEUE_FAILED" }
    end
    local directions = { "left", "right", "down", "up" }
    for _, direction in ipairs(directions) do
        local result, candidate = ops.scan(direction)
        if type(result) == "table" and result.ok ~= true then
            return { ok = false, code = result.code or "MAIN_SCAN_FAILED", direction = direction }
        elseif result ~= true and type(result) ~= "table" then
            return { ok = false, code = "MAIN_SCAN_FAILED", direction = direction }
        end
        if type(result) == "table" and result.ok == true and candidate == nil
            and result.code == "ORE_CANDIDATE_FOUND" then
            return { ok = false, code = "MAIN_SCAN_CANDIDATE_MISSING", direction = direction }
        end
        if candidate then
            local added, code = queue.add(candidate)
            if added ~= true then
                return { ok = false, code = code or "MAIN_SCAN_QUEUE_FAILED", direction = direction }
            end
        end
    end

    local finalPose = ops.pose()
    if ops.facing() ~= initialFacing or finalPose.x ~= checkpoint.x
        or finalPose.y ~= checkpoint.y or finalPose.z ~= checkpoint.z
        or finalPose.facing ~= checkpoint.facing then
        return { ok = false, code = "MAIN_SCAN_POSE_CHANGED" }
    end
    local drained = ops.drainCandidates(queue, checkpoint)
    if type(drained) ~= "table" or drained.ok ~= true then
        return { ok = false, code = type(drained) == "table"
            and drained.code or "MAIN_SCAN_QUEUE_DRAIN_FAILED" }
    end
    return { ok = true, code = "MAIN_SCAN_COMPLETE" }
end

return MainTunnelScan
