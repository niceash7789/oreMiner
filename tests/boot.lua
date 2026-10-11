local function boot(files, turtleApi, runResult)
    local calls = {}
    local environment = setmetatable({
        turtle = turtleApi,
        fs = {
            getDir = function(path)
                assert(path == "/oreMiner/boot.lua")
                return "/oreMiner"
            end,
            combine = function(left, right) return left .. "/" .. right end,
            exists = function(path) return files[path] == true end,
        },
        shell = {
            getRunningProgram = function() return "/oreMiner/boot.lua" end,
            dir = function() return "/" end,
            setDir = function(path) calls[#calls + 1] = { "dir", path } end,
            run = function(...)
                calls[#calls + 1] = { "run", ... }
                return runResult ~= false
            end,
        },
    }, { __index = _G })
    local chunk = assert(loadfile("boot.lua", "t", environment))
    local ok = pcall(chunk)
    return calls, ok
end

local calls = boot({}, {})
assert(calls[1][2] == "/oreMiner" and calls[2][2] == "miner"
    and calls[2][3] == nil and calls[3][2] == "/",
    "fresh boot should open the normal new-run confirmation from the install directory")

for _, suffix in ipairs({ "", ".bak", ".tmp" }) do
    calls = boot({ ["/oreMiner/oreMiner/state.json" .. suffix] = true }, {})
    assert(calls[2][2] == "miner" and calls[2][3] == "resume",
        "saved state should always take the safe resume path")
end

calls = boot({}, nil)
assert(#calls == 0, "non-turtle boot should be inert")

local failed, ok = boot({}, {}, false)
assert(not ok and failed[3][2] == "/",
    "failed miner launch should restore the previous shell directory")

print("boot checks passed")
