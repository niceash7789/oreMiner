-- Entry point called by the turtle's /startup/oreminer.lua hook.
if type(turtle) ~= "table" then return end
if type(fs) ~= "table" or type(shell) ~= "table"
    or type(shell.getRunningProgram) ~= "function"
    or type(shell.setDir) ~= "function" or type(shell.run) ~= "function" then
    error("oreMiner boot requires the CC:Tweaked filesystem and shell APIs")
end

local installDirectory = fs.getDir(shell.getRunningProgram())
local statePath = fs.combine(installDirectory, "oreMiner/state.json")
local hasState = fs.exists(statePath) or fs.exists(statePath .. ".bak")
    or fs.exists(statePath .. ".tmp")
local previousDirectory = shell.dir()
shell.setDir(installDirectory)
local ok, launched
if hasState then
    ok, launched = pcall(shell.run, "miner", "resume")
else
    ok, launched = pcall(shell.run, "miner")
end
shell.setDir(previousDirectory)
if not ok then error("oreMiner boot failed: " .. tostring(launched), 0) end
if not launched then error("oreMiner boot could not launch miner", 0) end
