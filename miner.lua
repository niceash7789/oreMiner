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

local loaded, runtimeError = pcall(dofile, baselinePath, ...)
if not loaded then
    error("oreMiner active baseline failed: " .. tostring(runtimeError))
end
