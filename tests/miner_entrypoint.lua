local function runWith(overrides, ...)
    local environment = {}
    for key, value in pairs(_G) do
        environment[key] = value
    end
    for key, value in pairs(overrides) do
        environment[key] = value
    end

    local chunk, loadError = loadfile("miner.lua", "t", environment)
    assert(chunk, loadError)
    return pcall(chunk, ...)
end

local loadedPath
local loadedArguments
local ok, result = runWith({
    turtle = {},
    require = function() return {} end,
    os = { epoch = function() return 0 end },
    shell = {
        getRunningProgram = function()
            return "disk/oreMiner/miner.lua"
        end,
    },
    fs = {
        getDir = function(path)
            assert(path == "disk/oreMiner/miner.lua", "launcher should resolve from its own path")
            return "disk/oreMiner"
        end,
        combine = function(directory, path)
            return directory .. "/" .. path
        end,
        exists = function(path)
            return path == "disk/oreMiner/src/branch_miner.lua"
        end,
    },
    dofile = function(path, ...)
        loadedPath = path
        loadedArguments = { ... }
    end,
}, "status", "--read-only")

assert(ok, result)
assert(
    loadedPath == "disk/oreMiner/src/branch_miner.lua",
    "launcher should execute the writable source baseline"
)
assert(loadedArguments[1] == "status" and loadedArguments[2] == "--read-only",
    "launcher should forward CLI arguments to the active baseline")

ok, result = runWith({
    turtle = {},
    require = function() return {} end,
    os = { epoch = function() return 0 end },
    shell = { getRunningProgram = function() return "miner.lua" end },
    fs = {
        getDir = function() return "" end,
        combine = function(_, path) return path end,
        exists = function() return false end,
    },
})

assert(ok == false, "launcher should fail when the baseline is absent")
assert(tostring(result):find("active baseline not found", 1, true), "missing baseline error should be specific")

ok, result = runWith({ turtle = false })
assert(ok == false, "launcher should reject non-turtle computers")
assert(tostring(result):find("must be run on a CC:Tweaked turtle", 1, true), "turtle error should be specific")

ok, result = runWith({ turtle = {}, require = false, os = { epoch = function() return 0 end } })
assert(ok == false, "launcher should reject runtimes without require")
assert(tostring(result):find("requires the CC:Tweaked require, os.epoch, fs, and shell APIs", 1, true),
    "missing module loader error should explain the runtime requirement")

ok, result = runWith({ turtle = {}, require = function() end, os = {} })
assert(ok == false, "launcher should reject runtimes without os.epoch")
assert(tostring(result):find("requires the CC:Tweaked require, os.epoch, fs, and shell APIs", 1, true),
    "missing clock API error should explain the runtime requirement")

print("miner entrypoint checks passed")
