-- Defer shaft ore work until a complete bounded slice returns to its anchor.
local Queue = {}

local function validPose(pose)
    return type(pose) == "table"
        and type(pose.x) == "number" and pose.x == math.floor(pose.x)
        and type(pose.y) == "number" and pose.y == math.floor(pose.y)
        and type(pose.z) == "number" and pose.z == math.floor(pose.z)
        and type(pose.facing) == "number" and pose.facing == math.floor(pose.facing)
        and pose.facing >= 0 and pose.facing <= 3
end

local function samePose(left, right)
    return left.x == right.x and left.y == right.y
        and left.z == right.z and left.facing == right.facing
end

function Queue.new(checkpoint)
    if not validPose(checkpoint) then return nil, "INVALID_ORE_QUEUE_CHECKPOINT" end
    local anchor = { x = checkpoint.x, y = checkpoint.y, z = checkpoint.z, facing = checkpoint.facing }
    local candidates = {}
    local seen = {}
    local queue = {}

    function queue.add(candidate)
        if not validPose(candidate) then return false, "INVALID_ORE_CANDIDATE" end
        local key = candidate.x .. "," .. candidate.y .. "," .. candidate.z
        if seen[key] then return true, "ORE_CANDIDATE_DUPLICATE" end
        seen[key] = true
        candidates[#candidates + 1] = {
            x = candidate.x, y = candidate.y, z = candidate.z,
            facing = candidate.facing,
        }
        return true, "ORE_CANDIDATE_QUEUED"
    end

    function queue.size()
        return #candidates
    end

    function queue.drain(currentPose, execute)
        if not validPose(currentPose) or not samePose(currentPose, anchor) then
            return { ok = false, code = "ORE_QUEUE_CHECKPOINT_MISMATCH", completed = 0 }
        end
        if type(execute) ~= "function" then
            return { ok = false, code = "ORE_QUEUE_INVALID_EXECUTOR", completed = 0 }
        end
        for index, candidate in ipairs(candidates) do
            local outcome = execute(candidate, index)
            if outcome ~= true and not (type(outcome) == "table" and outcome.ok == true) then
                return {
                    ok = false,
                    code = type(outcome) == "table" and outcome.code or "ORE_QUEUE_EXECUTION_FAILED",
                    completed = index - 1,
                }
            end
        end
        local completed = #candidates
        candidates, seen = {}, {}
        return { ok = true, code = "ORE_QUEUE_DRAINED", completed = completed }
    end

    return queue
end

return Queue
