-- Read-only rendering for persisted run recovery state.
local RecoveryStatus = {}
local Recovery = require("src.persistence.recovery")

local function poseText(pose)
    return string.format("%d,%d,%d f%d", pose.x, pose.y, pose.z, pose.facing)
end

local function progressText(progress)
    return string.format("%s %s:%d/%d", progress.phase, progress.side,
        progress.offset, progress.mainOffset)
end

function RecoveryStatus.lines(state, loadCode, fuel, occupiedSlots, threshold)
    local lines = {}
    if not state then
        lines[#lines + 1] = "Run: " .. tostring(loadCode)
        lines[#lines + 1] = "Pose: unavailable"
        lines[#lines + 1] = "Certainty: unknown"
        lines[#lines + 1] = "Progress: unavailable"
        lines[#lines + 1] = "Fuel: " .. tostring(fuel)
        lines[#lines + 1] = "Inventory: " .. tostring(occupiedSlots) .. "/" .. tostring(threshold)
        lines[#lines + 1] = "Last error: unavailable"
        return lines
    end

    lines[#lines + 1] = "Run: " .. tostring(state.status)
    lines[#lines + 1] = "Pose: " .. poseText(state.pose)
    lines[#lines + 1] = "Certainty: " .. tostring(state.poseCertainty)
    lines[#lines + 1] = "Progress: " .. progressText(state.progress)
    lines[#lines + 1] = "Fuel: " .. tostring(fuel)
    lines[#lines + 1] = "Inventory: " .. tostring(occupiedSlots) .. "/" .. tostring(threshold)
    lines[#lines + 1] = "Last error: " .. tostring(state.error or "none")
    local resumable, reason = Recovery.classify(state, loadCode)
    lines[#lines + 1] = resumable
        and "Recovery: safe checkpoint"
        or "Recovery: stopped (" .. tostring(reason) .. ")"
    if loadCode == "POSITION_UNCERTAIN" then
        lines[#lines + 1] = "Recovery: pending action; do not move"
    elseif loadCode == "STATE_RECOVERED_BACKUP" then
        lines[#lines + 1] = "Recovery: loaded backup snapshot"
    end
    return lines
end

function RecoveryStatus.display(state, loadCode, fuel, occupiedSlots, threshold, sink)
    if type(sink) ~= "function" then return false, "STATUS_SINK_UNAVAILABLE" end
    for _, line in ipairs(RecoveryStatus.lines(state, loadCode, fuel, occupiedSlots, threshold)) do
        local ok = pcall(sink, line)
        if not ok then return false, "STATUS_OUTPUT_FAILED" end
    end
    return true, "STATUS_DISPLAYED"
end

return RecoveryStatus
