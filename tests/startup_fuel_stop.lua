local files = {}
local moves = 0
local selected = 1

local turtleApi = {
    getFuelLevel = function() return 0 end,
    getSelectedSlot = function() return selected end,
    select = function(slot) selected = slot return true end,
    getItemCount = function() return 0 end,
    getItemDetail = function() return nil end,
    refuel = function() return false end,
    forward = function() moves = moves + 1 return true end,
    back = function() moves = moves + 1 return true end,
    up = function() moves = moves + 1 return true end,
    down = function() moves = moves + 1 return true end,
    turnLeft = function() moves = moves + 1 return true end,
    turnRight = function() moves = moves + 1 return true end,
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
environment.sleep = function() end
environment.write = function() end
environment.read = function() inputIndex = inputIndex + 1 return inputs[inputIndex] end
environment.print = function() end

local chunk, loadError = loadfile("src/branch_miner.lua", "t", environment)
assert(chunk, loadError)
local ok, runtimeError = pcall(chunk)
assert(ok, runtimeError)
assert(moves == 0, "insufficient startup fuel must stop before movement or turning")

local saved = assert(files["oreMiner/state.json"], "fatal fuel stop should remain durable")
local state = assert(load("return " .. saved))()
assert(state.status == "error" and state.error == "NO_FUEL",
    "startup fuel failure should persist NO_FUEL")

print("startup fuel stop checks passed")
