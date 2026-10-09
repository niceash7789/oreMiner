local MainTunnelScan = require("src.mining.main_tunnel_scan")

local facing = 0
local inspected = {}
local pose = { x = 0, y = 2, z = 4, facing = 0 }
local created = 0
local drained = 0
local result = MainTunnelScan.scanCell({
    facing = function() return facing end,
    pose = function() return { x = pose.x, y = pose.y, z = pose.z, facing = pose.facing } end,
    candidateQueue = function(anchor)
        created = created + 1
        local candidates = {}
        return {
            add = function(candidate) candidates[#candidates + 1] = candidate; return true end,
            size = function() return #candidates end,
            candidates = candidates,
        }
    end,
    drainCandidates = function(queue, checkpoint)
        assert(checkpoint.x == pose.x and checkpoint.facing == pose.facing)
        drained = drained + 1
        return { ok = true }
    end,
    scan = function(direction)
        inspected[#inspected + 1] = direction
        if direction == "left" then facing = 3
        elseif direction == "right" then facing = 0
        end
        return true
    end,
})
assert(result.ok and result.code == "MAIN_SCAN_COMPLETE")
assert(table.concat(inspected, ",") == "left,right,down,up")
assert(facing == 0, "scan must preserve tunnel facing")
assert(created == 1 and drained == 1, "one queue is drained once at the cell checkpoint")

local attempts = 0
result = MainTunnelScan.scanCell({
    facing = function() return 0 end,
    pose = function() return { x = 0, y = 0, z = 0, facing = 0 } end,
    candidateQueue = function() return { add = function() return true end, size = function() return 0 end } end,
    drainCandidates = function() return { ok = true } end,
    scan = function(direction)
        attempts = attempts + 1
        return direction ~= "right"
    end,
})
assert(not result.ok and result.code == "MAIN_SCAN_FAILED")
assert(result.direction == "right" and attempts == 2,
    "scan failure must stop before attempting further directions")

local movingPose = { x = 0, y = 0, z = 0, facing = 0 }
result = MainTunnelScan.scanCell({
    facing = function() return 0 end,
    pose = function() return movingPose end,
    candidateQueue = function() return { add = function() return true end, size = function() return 0 end } end,
    drainCandidates = function() return { ok = true } end,
    scan = function(direction)
        if direction == "down" then
            return { ok = false, code = "VEIN_RETURN_BLOCKED" }
        end
        return true
    end,
})
assert(not result.ok and result.code == "VEIN_RETURN_BLOCKED",
    "vein return failures must propagate to the main scan caller")

local changedPose = { x = 0, y = 0, z = 0, facing = 0 }
result = MainTunnelScan.scanCell({
    facing = function() return 0 end,
    pose = function() return { x = changedPose.x, y = changedPose.y,
        z = changedPose.z, facing = changedPose.facing } end,
    candidateQueue = function() return { add = function() return true end, size = function() return 0 end } end,
    drainCandidates = function() return { ok = true } end,
    scan = function(direction)
        if direction == "up" then changedPose.y = changedPose.y + 1 end
        return true
    end,
})
assert(not result.ok and result.code == "MAIN_SCAN_POSE_CHANGED",
    "queue drain is forbidden after a scan callback changes the checkpoint pose")

print("main tunnel scan checks passed")
