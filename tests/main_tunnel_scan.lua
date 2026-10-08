local MainTunnelScan = require("src.mining.main_tunnel_scan")

local facing = 0
local inspected = {}
local result = MainTunnelScan.scanCell({
    facing = function() return facing end,
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

local attempts = 0
result = MainTunnelScan.scanCell({
    facing = function() return 0 end,
    scan = function(direction)
        attempts = attempts + 1
        return direction ~= "right"
    end,
})
assert(not result.ok and result.code == "MAIN_SCAN_FAILED")
assert(result.direction == "right" and attempts == 2,
    "scan failure must stop before attempting further directions")

result = MainTunnelScan.scanCell({
    facing = function() return 0 end,
    scan = function(direction)
        if direction == "down" then
            return { ok = false, code = "VEIN_RETURN_BLOCKED" }
        end
        return true
    end,
})
assert(not result.ok and result.code == "VEIN_RETURN_BLOCKED",
    "vein return failures must propagate to the main scan caller")

print("main tunnel scan checks passed")
