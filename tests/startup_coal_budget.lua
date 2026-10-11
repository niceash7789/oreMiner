-- A short-route startup must not burn coal toward the whole job estimate.
local fileConfig = require("tests.config_fixture")
local StairRoute = require("src.navigation.stair_route")
local Resupply = require("src.inventory.resupply")
local MiningCursor = require("src.mining.cursor")

local originalDescend = StairRoute.descend
local originalResupply = Resupply.run
local originalMainShaft = MiningCursor.mainShaft
local files = {}
local selected, coal, fuel, refuelCalls = 1, 64, 109, 0

StairRoute.descend = function(options)
    return options.pose, { ok = true, code = "TEST_LANDING" }
end
Resupply.run = function()
    return { ok = true, code = "RESUPPLY_COMPLETE" }
end
MiningCursor.mainShaft = function()
    error("FIRST_MINING_MOVE")
end

local turtleApi = {
    getFuelLevel = function() return fuel end,
    getSelectedSlot = function() return selected end,
    select = function(slot) selected = slot return true end,
    getItemCount = function(slot) return slot == 2 and coal or 0 end,
    getItemDetail = function(slot)
        if slot == 2 and coal > 0 then return { name = "minecraft:coal" } end
    end,
    refuel = function(amount)
        if amount == 0 then return selected == 2 and coal > 0 end
        refuelCalls = refuelCalls + 1
        if selected ~= 2 or coal == 0 then return false end
        coal, fuel = coal - 1, fuel + 80
        return true
    end,
    inspect = function() return true, { name = "minecraft:chest" } end,
    turnLeft = function() return true end,
    turnRight = function() return true end,
}

local function serialize(value)
    if type(value) == "table" then
        local parts = {}
        for key, child in pairs(value) do
            local rendered = type(key) == "string" and "[" .. string.format("%q", key) .. "]"
                or "[" .. tostring(key) .. "]"
            parts[#parts + 1] = rendered .. "=" .. serialize(child)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    if type(value) == "string" then return string.format("%q", value) end
    return tostring(value)
end

local environment = {}
for key, value in pairs(_G) do environment[key] = value end
environment.turtle = turtleApi
environment.require = function(name)
    if name == "config" then return fileConfig end
    return require(name)
end
environment.fs = {
    exists = function(path) return files[path] ~= nil end,
    makeDir = function() end,
    combine = function(left, right) return left .. "/" .. right end,
    open = function(path, mode)
        if mode == "r" then
            local content = files[path]
            if not content then return nil end
            return { readAll = function() return content end, close = function() end }
        end
        local content = ""
        return {
            write = function(value) content = content .. value end,
            close = function() files[path] = content end,
        }
    end,
    delete = function(path) files[path] = nil end,
    move = function(source, target)
        files[target], files[source] = files[source], nil
    end,
}
environment.textutils = {
    serialize = serialize,
    unserialize = function(value) return load("return " .. value)() end,
}
environment.os = {}
for key, value in pairs(os) do environment.os[key] = value end
environment.os.epoch = function() return 0 end
environment.print = function() end
environment.write = function() end
environment.read = function() return "y" end

local chunk, loadError = loadfile("src/branch_miner.lua", "t", environment)
assert(chunk, loadError)
local ok, runtimeError = pcall(chunk)

StairRoute.descend = originalDescend
Resupply.run = originalResupply
MiningCursor.mainShaft = originalMainShaft

assert(not ok and tostring(runtimeError):find("FIRST_MINING_MOVE", 1, true),
    "test must reach the first floor-mining action")
assert(refuelCalls == 0 and coal == 64 and fuel == 109,
    "startup must not consume coal toward a whole-job estimate")

print("startup coal budget checks passed")
