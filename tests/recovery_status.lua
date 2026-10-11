local RecoveryStatus = require("src.reporting.recovery_status")

local progress = {
    workDomain = "floor", workUnitId = "floor-1-pair-1-main", floor = 1,
    stairSegment = 0, stairStep = 0, branchPair = 1, side = "none",
    phase = "main_shaft", offset = 2, mainOffset = 0, nextAction = "mine_main_cell",
}
local state = {
    status = "mining", pose = { x = 2, y = -8, z = -4, facing = 1 },
    poseCertainty = "known", progress = progress, error = nil,
    resumeCheckpoint = {
        pose = { x = 2, y = -8, z = -4, facing = 1 }, progress = progress,
    },
    route = { home = "0,0,0", edges = {} },
}
local lines = RecoveryStatus.lines(state, "STATE_LOADED", 120, 7, 14)
assert(lines[1] == "Run: mining" and lines[2] == "Pose: 2,-8,-4 f1")
assert(lines[3] == "Certainty: known" and lines[4] == "Progress: main_shaft none:2/0")
assert(lines[5] == "Fuel: 120" and lines[6] == "Inventory: 7/14" and lines[7] == "Last error: none")
assert(lines[8] == "Recovery: stopped (MAIN_SHAFT_RESUME_UNSUPPORTED)",
    "status should expose the classifier's exact restart restriction")

local uncertain = RecoveryStatus.lines(state, "POSITION_UNCERTAIN", 99, 14, 14)
assert(uncertain[3] == "Certainty: known", "renderer must report stored value accurately")
assert(uncertain[#uncertain] == "Recovery: pending action; do not move")
local missing = RecoveryStatus.lines(nil, "STATE_MISSING", "unlimited", 0, 14)
assert(missing[1] == "Run: STATE_MISSING" and missing[3] == "Certainty: unknown")

local output = {}
assert(RecoveryStatus.display(state, "STATE_LOADED", 120, 7, 14,
    function(line) output[#output + 1] = line end))
assert(#output == 8)
local displayed, outputCode = RecoveryStatus.display(state, "STATE_LOADED", 120, 7, 14,
    function() error("terminal unavailable") end)
assert(not displayed and outputCode == "STATUS_OUTPUT_FAILED")

local function runCommand(command, stateCode)
    local captured = {}
    local fakeFs = {
        combine = function(_, file) return file end,
        exists = function(path) return path == "state.json" and stateCode ~= "STATE_MISSING" end,
        open = function(path)
            if path ~= "state.json" then return nil end
            return { readAll = function() return "snapshot" end, close = function() end }
        end,
    }
    local fakeTextutils = {
        unserialize = function()
            if stateCode == "POSITION_UNCERTAIN" then
                local pending = {}
                for key, value in pairs(state) do pending[key] = value end
                pending.pendingAction = { kind = "move", direction = "forward" }
                pending.poseCertainty = "uncertain"
                return pending
            end
            return state
        end,
    }
    local fakeTurtle = {
        getFuelLevel = function() return 120 end,
        getItemCount = function() return 0 end,
        forward = function() error("status command must not move") end,
        back = function() error("status command must not move") end,
        up = function() error("status command must not move") end,
        down = function() error("status command must not move") end,
        turnLeft = function() error("status command must not turn") end,
        turnRight = function() error("status command must not turn") end,
        dig = function() error("status command must not dig") end,
    }
    local originalRequire, originalPrint = require, print
    local modules = {
        ["config"] = require("tests.config_fixture"),
        ["src.config.loader"] = require("src.config.loader"),
        ["src.reporting.recovery_status"] = RecoveryStatus,
        ["src.persistence.checkpoint"] = {
            load = function()
                if stateCode == "STATE_MISSING" then return nil, "STATE_MISSING" end
                return {
                    status = function() return state.status end,
                    snapshotState = function() return state end,
                }, stateCode
            end,
        },
    }
    for _, name in ipairs({
        "src.navigation.pose", "src.navigation.motion", "src.navigation.turn",
        "src.inventory.slot_guard", "src.config.item_policy", "src.mining.ore_classifier",
        "src.reporting.status", "src.reporting.safe",
        "src.fuel.known_route", "src.mining.vein_traversal", "src.safety.dig_clear",
        "src.safety.forward_recovery", "src.safety.result", "src.mining.branch_progress",
        "src.navigation.branch_traversal", "src.navigation.floor_grid", "src.navigation.return_move",
        "src.navigation.route_home", "src.fuel.resume_commitment", "src.navigation.stair_route",
        "src.navigation.floor_landing", "src.mining.main_tunnel_scan", "src.mining.main_shaft_backfill",
        "src.lighting.right_wall", "src.inventory.service", "src.inventory.resupply",
        "src.inventory.branch_ejection", "src.mining.cursor",
    }) do
        modules[name] = {}
    end
    modules["src.navigation.pose"] = require("src.navigation.pose")
    modules["src.fuel.known_route"] = require("src.fuel.known_route")
    modules["src.inventory.service"] = require("src.inventory.service")
    modules["src.reporting.safe"] = require("src.reporting.safe")
    modules["src.reporting.statistics"] = {
        new = function() return { add = function() end, get = function() return 0 end } end,
    }
    local env = setmetatable({
        turtle = fakeTurtle, fs = fakeFs, textutils = fakeTextutils,
        print = function(line) captured[#captured + 1] = line end,
        write = function() end, read = function() return "n" end,
        os = { epoch = function() return 1 end },
        require = function(name)
            if modules[name] ~= nil then
                return modules[name]
            end
            return originalRequire(name)
        end,
    }, { __index = _G })
    local chunk = assert(loadfile("src/branch_miner.lua", "t", env))
    local ok, result = pcall(chunk, command)
    assert(ok, result)
    return captured
end

local commandLines = runCommand("status", "STATE_LOADED")
assert(commandLines[1] == "Run: mining" and commandLines[4] == "Progress: main_shaft none:2/0")
local missingLines = runCommand("status", "STATE_MISSING")
assert(missingLines[1] == "Run: STATE_MISSING")
local resumeLines = runCommand("resume", "STATE_LOADED")
assert(resumeLines[1]:find("Resume stopped safely", 1, true))

print("recovery status tests passed")
