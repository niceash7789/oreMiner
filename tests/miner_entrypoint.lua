local function runWith(overrides)
    local environment = {}
    for key, value in pairs(_G) do
        environment[key] = value
    end
    for key, value in pairs(overrides) do
        environment[key] = value
    end

    local chunk, loadError = loadfile("miner.lua", "t", environment)
    assert(chunk, loadError)
    return pcall(chunk)
end

local loadedPath
local ok, result = runWith({
    turtle = {},
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
    dofile = function(path)
        loadedPath = path
    end,
})

assert(ok, result)
assert(
    loadedPath == "disk/oreMiner/src/branch_miner.lua",
    "launcher should execute the writable source baseline"
)

ok, result = runWith({
    turtle = {},
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

print("miner entrypoint checks passed")
