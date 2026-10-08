-- Scans one already-cleared main-tunnel cell around the turtle's current pose.
local MainTunnelScan = {}

function MainTunnelScan.scanCell(ops)
    if type(ops) ~= "table" or type(ops.scan) ~= "function" then
        return { ok = false, code = "MAIN_SCAN_INVALID_OPS" }
    end

    local initialFacing = ops.facing()
    local directions = { "left", "right", "down", "up" }
    for _, direction in ipairs(directions) do
        local result = ops.scan(direction)
        if type(result) == "table" and result.ok ~= true then
            return { ok = false, code = result.code or "MAIN_SCAN_FAILED", direction = direction }
        elseif result ~= true and type(result) ~= "table" then
            return { ok = false, code = "MAIN_SCAN_FAILED", direction = direction }
        end
    end

    if ops.facing() ~= initialFacing then
        return { ok = false, code = "MAIN_SCAN_POSE_CHANGED" }
    end
    return { ok = true, code = "MAIN_SCAN_COMPLETE" }
end

return MainTunnelScan
