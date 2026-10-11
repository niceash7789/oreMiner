-- Select the operator configuration, falling back to the tracked example only
-- when no live config exists. A broken live config must never be bypassed.
local Source = {}

function Source.load(fileSystem, shellApi, requireModule, runFile)
    if type(fileSystem) == "table" and type(fileSystem.exists) == "function"
        and type(fileSystem.getDir) == "function"
        and type(fileSystem.combine) == "function"
        and type(shellApi) == "table"
        and type(shellApi.getRunningProgram) == "function" then
        local root = fileSystem.getDir(shellApi.getRunningProgram())
        local livePath = fileSystem.combine(root, "config.lua")
        local examplePath = fileSystem.combine(root, "config.example.lua")
        local selectedPath = fileSystem.exists(livePath) and livePath or examplePath
        if not fileSystem.exists(selectedPath) then
            return nil, selectedPath, "configuration file is missing"
        end
        local ok, value = pcall(runFile, selectedPath)
        if not ok then return nil, selectedPath, tostring(value) end
        return value, selectedPath
    end

    -- The coordinator's isolated test harness provides modules without a CC
    -- shell or filesystem. Its existing injected config module remains usable.
    local ok, value = pcall(requireModule, "config")
    if not ok then return nil, "config.lua", tostring(value) end
    return value, "config.lua"
end

return Source
