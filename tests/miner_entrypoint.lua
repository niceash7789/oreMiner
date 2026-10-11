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
    local ok, result = pcall(chunk, ...)
    return ok, result, environment
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
        open = function(path, mode)
            assert(path == "disk/oreMiner/src/branch_miner.lua" and mode == "r")
            return { readAll = function() return "capture(require, ...)" end, close = function() end }
        end,
    },
    capture = function(moduleLoader, ...)
        loadedPath = "disk/oreMiner/src/branch_miner.lua"
        loadedArguments = { ... }
        assert(type(moduleLoader) == "function")
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
        open = function() return nil end,
    },
})

assert(ok == false, "launcher should fail when the baseline is absent")
assert(tostring(result):find("active baseline not found", 1, true), "missing baseline error should be specific")

ok, result = runWith({ turtle = false })
assert(ok == false, "launcher should reject non-turtle computers")
assert(tostring(result):find("must be run on a CC:Tweaked turtle", 1, true), "turtle error should be specific")

local loadedModule
local fallbackEnvironment
ok, result, fallbackEnvironment = runWith({
    turtle = {},
    require = false,
    os = { epoch = function() return 0 end },
    shell = { getRunningProgram = function() return "miner.lua" end },
    fs = {
        getDir = function() return "" end,
        combine = function(_, path) return path end,
        exists = function() return true end,
        open = function(path)
            local source
            if path == "src/branch_miner.lua" then
                source = "capture(require, ...)"
            elseif path == "src/fixture.lua" then
                source = "return { answer = 42 }"
            end
            if not source then return nil end
            return { readAll = function() return source end, close = function() end }
        end,
    },
    capture = function(moduleLoader) loadedModule = moduleLoader end,
})
assert(ok, result)
assert(type(loadedModule) == "function", "launcher should provide a module loader when require is absent")
assert(fallbackEnvironment.require("src.fixture").answer == 42,
    "fallback loader should load repository modules")
assert(fallbackEnvironment.require("src.fixture").answer == 42,
    "fallback loader should cache loaded modules")

ok, result = runWith({ turtle = {}, require = function() end, os = {} })
assert(ok == false, "launcher should reject runtimes without os.epoch")
assert(tostring(result):find("requires the CC:Tweaked os.epoch, filesystem, Lua load/setmetatable, and shell APIs", 1, true),
    "missing clock API error should explain the runtime requirement")

ok, result = runWith({
    turtle = {},
    require = function() end,
    os = { epoch = function() return 0 end },
    shell = { getRunningProgram = function() return "miner.lua" end },
    fs = {
        getDir = function() return "" end,
        combine = function(_, path) return path end,
        exists = function() return true end,
        open = function(path)
            if path == "src/branch_miner.lua" then
                return { readAll = function() return "error(\"test failure\")" end, close = function() end }
            end
            return nil
        end,
    },
})
assert(ok == false, "launcher should report runtime errors from the active file")
assert(tostring(result):find("active baseline failed: .*test failure"),
    "runtime errors should include the active source failure")

print("miner entrypoint checks passed")
