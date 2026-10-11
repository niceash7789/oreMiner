local Source = require("src.config.source")

local files = {
    ["disk/oreMiner/config.example.lua"] = true,
}
local executed = {}
local fileSystem = {
    getDir = function(path)
        assert(path == "disk/oreMiner/miner.lua")
        return "disk/oreMiner"
    end,
    combine = function(root, name) return root .. "/" .. name end,
    exists = function(path) return files[path] == true end,
}
local shellApi = { getRunningProgram = function() return "disk/oreMiner/miner.lua" end }
local function requireModule()
    error("CC runtime must load the selected file")
end
local function runFile(path)
    executed[#executed + 1] = path
    if path == "disk/oreMiner/config.lua" then error("invalid live config") end
    return { schemaVersion = 1 }
end

local config, path, err = Source.load(fileSystem, shellApi, requireModule, runFile)
assert(config.schemaVersion == 1 and path == "disk/oreMiner/config.example.lua" and err == nil)
assert(#executed == 1 and executed[1] == path)

files["disk/oreMiner/config.lua"] = true
config, path, err = Source.load(fileSystem, shellApi, requireModule, runFile)
assert(config == nil and path == "disk/oreMiner/config.lua")
assert(err:find("invalid live config", 1, true))
assert(#executed == 2 and executed[2] == path, "a broken live config must not fall back")

files["disk/oreMiner/config.lua"] = nil
files["disk/oreMiner/config.example.lua"] = nil
config, path, err = Source.load(fileSystem, shellApi, requireModule, runFile)
assert(config == nil and path == "disk/oreMiner/config.example.lua")
assert(err == "configuration file is missing" and #executed == 2)

config, path, err = Source.load({}, nil, function(name)
    assert(name == "config")
    return { schemaVersion = 1 }
end, runFile)
assert(config.schemaVersion == 1 and path == "config.lua" and err == nil)

local Loader = require("src.config.loader")
local exampleFs = {
    getDir = function() return "" end,
    combine = function(_, name) return name end,
    exists = function(path) return path == "config.example.lua" end,
}
local example, examplePath, exampleError = Source.load(exampleFs,
    { getRunningProgram = function() return "miner.lua" end }, requireModule, dofile)
assert(examplePath == "config.example.lua" and exampleError == nil)
local normalized, outcome = Loader.normalize(example)
assert(normalized and outcome.ok, "the tracked example must validate")

print("configuration source selection checks passed")
