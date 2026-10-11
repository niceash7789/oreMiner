-- Entry point for the writable phase-one baseline under src/.
-- MINER_PLAN.md tasks progressively extract corrected modules and reduce
-- src/branch_miner.lua to the high-level coordinator.

if type(turtle) ~= "table" then
    error("oreMiner must be run on a CC:Tweaked turtle.")
end

if type(fs) ~= "table"
    or type(fs.getDir) ~= "function"
    or type(fs.combine) ~= "function"
    or type(fs.exists) ~= "function"
    or type(require) ~= "function"
    or type(os) ~= "table"
    or type(os.epoch) ~= "function"
    or type(shell) ~= "table"
    or type(shell.getRunningProgram) ~= "function" then
    error("oreMiner requires the CC:Tweaked require, os.epoch, fs, and shell APIs. Run it with the CC:Tweaked Lua runtime.")
end

local programPath = shell.getRunningProgram()
local programDirectory = fs.getDir(programPath)
local baselinePath = fs.combine(programDirectory, "src/branch_miner.lua")

if not fs.exists(baselinePath) then
    error("oreMiner active baseline not found: " .. baselinePath)
end

-- CC:Tweaked's dofile executes files in an environment whose require resolves
-- module paths from the running program. If that loader is absent, report it
-- here instead of wrapping the resulting nil-global error on this launcher line.
if type(require) ~= "function" then
    error("oreMiner cannot load modules because global 'require' is unavailable; run it in the CC:Tweaked shell and update with 'git pull'.")
end

local loaded, runtimeError = pcall(dofile, baselinePath, ...)
if not loaded then
    local message = tostring(runtimeError)
    if message:find("global 'require'", 1, true)
        or message:find("global 'require'", 1, true) then
        error("oreMiner cannot load modules because global 'require' is unavailable; run it in the CC:Tweaked shell and update with 'git pull'. Original error: " .. message)
    end
    error("oreMiner active baseline failed: " .. message)
end
