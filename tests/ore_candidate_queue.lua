local OreCandidateQueue = require("src.mining.ore_candidate_queue")

local checkpoint = { x = 4, y = -8, z = 10, facing = 1 }
local queue = assert(OreCandidateQueue.new(checkpoint))
assert(queue.add({ x = 4, y = -8, z = 11, facing = 1 }))
assert(queue.add({ x = 5, y = -8, z = 10, facing = 0 }))
assert(queue.size() == 2)

local executed = 0
local wrongCheckpoint = queue.drain({ x = 4, y = -8, z = 10, facing = 0 }, function()
    executed = executed + 1
    return true
end)
assert(not wrongCheckpoint.ok and wrongCheckpoint.code == "ORE_QUEUE_CHECKPOINT_MISMATCH")
assert(executed == 0 and queue.size() == 2,
    "candidates must remain queued and unexecuted until the canonical pose is restored")

local order = {}
local drained = queue.drain(checkpoint, function(candidate, index)
    order[#order + 1] = candidate.x .. "," .. candidate.z
    assert(index == #order)
    return true
end)
assert(drained.ok and drained.completed == 2)
assert(order[1] == "4,11" and order[2] == "5,10", "queue must preserve discovery order")
assert(queue.size() == 0, "successful drain clears the slice queue")

queue.add({ x = 4, y = -8, z = 11, facing = 1 })
local failed = queue.drain(checkpoint, function() return { ok = false, code = "VEIN_RETURN_BLOCKED" } end)
assert(not failed.ok and failed.code == "VEIN_RETURN_BLOCKED" and queue.size() == 1,
    "a failed vein must stop the drain and retain uncompleted candidates")

print("ore candidate queue checks passed")
