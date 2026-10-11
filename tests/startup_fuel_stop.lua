local files = {}
local routeMoves = 0
local turns = 0
local selected = 1
require("tests.config_fixture")

local turtleApi = {
    getFuelLevel = function() return 0 end,
    getSelectedSlot = function() return selected end,
    select = function(slot) selected = slot return true end,
    getItemCount = function() return 0 end,
    getItemDetail = function() return nil end,
    refuel = function() return false end,
    suck = function() return false end,
    drop = function() return false end,
    inspect = function() return true, { name = "minecraft:chest" } end,
    forward = function() routeMoves = routeMoves + 1 return true end,
    back = function() routeMoves = routeMoves + 1 return true end,
    up = function() routeMoves = routeMoves + 1 return true end,
    down = function() routeMoves = routeMoves + 1 return true end,
    turnLeft = function() turns = turns + 1 return true end,
    turnRight = function() turns = turns + 1 return true end,
}

local function serialize(value)
    if type(value) == "table" then
        local entries = {}
        for key, child in pairs(value) do
            local rendered = type(key) == "string" and "[" .. string.format("%q", key) .. "]"
                or "[" .. tostring(key) .. "]"
            entries[#entries + 1] = rendered .. "=" .. serialize(child)
        end
        return "{" .. table.concat(entries, ",") .. "}"
    end
    if type(value) == "string" then return string.format("%q", value) end
    return tostring(value)
end

-- The file-backed configuration is now read-only at startup; only the final
-- confirmation prompt consumes input.
local inputs = { "y" }
local inputIndex = 0
local environment = {}
for key, value in pairs(_G) do environment[key] = value end
environment.turtle = turtleApi
environment.fs = {
    exists = function(path) return files[path] ~= nil end,
    makeDir = function() end,
    combine = function(left, right) return left .. "/" .. right end,
    open = function(path, mode)
        if mode == "r" then
            if files[path] == nil then return nil end
            local content = files[path]
            return { readAll = function() return content end, close = function() end }
        end
        local content = ""
        return {
            write = function(value) content = content .. value end,
            close = function() files[path] = content end,
        }
    end,
    delete = function(path) files[path] = nil end,
    move = function(source, target) files[target], files[source] = files[source], nil end,
}
environment.textutils = {
    serialize = serialize,
    unserialize = function(value) return load("return " .. value)() end,
}
environment.os = {}
for key, value in pairs(os) do environment.os[key] = value end
environment.os.epoch = function() return 0 end
local waits = 0
environment.sleep = function(seconds)
    assert(seconds == 5)
    waits = waits + 1
    error("STOP_AFTER_FIRST_SUPPLY_WAIT")
end
environment.write = function() end
environment.read = function() inputIndex = inputIndex + 1 return inputs[inputIndex] end
environment.print = function() end

local chunk, loadError = loadfile("src/branch_miner.lua", "t", environment)
assert(chunk, loadError)
local ok, runtimeError = pcall(chunk)
assert(not ok and tostring(runtimeError):find("STOP_AFTER_FIRST_SUPPLY_WAIT", 1, true),
    "temporary supply shortage should enter the bounded base retry")
assert(routeMoves == 0 and turns == 2 and waits == 1,
    "insufficient startup fuel must not start the mining route")

local saved = assert(files["oreMiner/state.json"], "supply wait should retain a durable checkpoint")
local state = assert(load("return " .. saved))()
assert(state.status == "mining" and state.pose.x == 0 and state.pose.y == 0
    and state.pose.z == 0 and state.pose.facing == 0,
    "temporary shortage should keep the saved run at its surface origin")
local resumable, recoveryCode = require("src.persistence.recovery").classify(
    state, "STATE_LOADED")
assert(resumable and recoveryCode == "RESUME_SAFE_CHECKPOINT"
    and state.progress.phase == "surface_entry",
    "a reboot during startup supply wait must preserve a dispatchable surface cursor")
local resumeChunk = assert(loadfile("src/branch_miner.lua", "t", environment))
local resumed, resumeError = pcall(resumeChunk, "resume")
assert(not resumed and tostring(resumeError):find("STOP_AFTER_FIRST_SUPPLY_WAIT", 1, true)
    and waits == 2 and routeMoves == 0,
    "resumed startup shortage must return to supply checks before route travel")

print("startup fuel stop checks passed")
