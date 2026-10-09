local source = require("config")
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

local chunk, loadError = loadfile("src/branch_miner.lua", "t", environment)
assert(chunk, loadError)
local ok, runtimeError = pcall(chunk)
source.schemaVersion = originalSchemaVersion

assert(not ok, "invalid file configuration must reject coordinator startup")
assert(tostring(runtimeError):find("CONFIG_INVALID", 1, true)
    and tostring(runtimeError):find("schemaVersion must be 1", 1, true),
    "startup should report the concrete configuration error")
assert(turtleCalls == 0, "configuration rejection must occur before every turtle action")

print("configuration startup rejection checks passed")
