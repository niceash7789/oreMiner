local source = require("tests.config_fixture")
local originalSchemaVersion = source.schemaVersion
source.schemaVersion = 2

local turtleCalls = 0
local turtleApi = setmetatable({}, {
    __index = function()
        return function()
            turtleCalls = turtleCalls + 1
            error("invalid configuration must stop before turtle APIs")
        end
    end,
})

local environment = {}
for key, value in pairs(_G) do environment[key] = value end
environment.turtle = turtleApi
environment.fs = {}
environment.textutils = {}
environment.require = function(name)
    if name == "config" then return source end
    return require(name)
end

local chunk, loadError = loadfile("src/branch_miner.lua", "t", environment)
assert(chunk, loadError)
local ok, runtimeError = pcall(chunk)
source.schemaVersion = originalSchemaVersion

assert(not ok, "invalid file configuration must reject coordinator startup")
assert(tostring(runtimeError):find("CONFIG_INVALID", 1, true)
    and tostring(runtimeError):find("schemaVersion must be 1", 1, true),
    "startup should report the concrete configuration error")
assert(turtleCalls == 0, "configuration rejection must occur before every turtle action")

local selectedPath
environment.fs = {
    getDir = function(path)
        assert(path == "disk/oreMiner/miner.lua")
        return "disk/oreMiner"
    end,
    combine = function(root, name) return root .. "/" .. name end,
    exists = function(path) return path == "disk/oreMiner/config.example.lua" end,
}
environment.shell = { getRunningProgram = function() return "disk/oreMiner/miner.lua" end }
environment.dofile = function(path)
    selectedPath = path
    return source
end
source.schemaVersion = 2
chunk, loadError = loadfile("src/branch_miner.lua", "t", environment)
assert(chunk, loadError)
ok, runtimeError = pcall(chunk)
source.schemaVersion = originalSchemaVersion
assert(not ok and selectedPath == "disk/oreMiner/config.example.lua")
assert(tostring(runtimeError):find("CONFIG_INVALID", 1, true)
    and tostring(runtimeError):find("schemaVersion must be 1", 1, true))
assert(turtleCalls == 0, "example fallback must validate before turtle actions")

print("configuration startup rejection checks passed")
