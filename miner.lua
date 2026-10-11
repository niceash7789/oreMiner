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
    or type(fs.open) ~= "function"
    or type(load) ~= "function"
    or type(os) ~= "table"
    or type(os.epoch) ~= "function"
    or type(shell) ~= "table"
    or type(shell.getRunningProgram) ~= "function" then
    error("oreMiner requires the CC:Tweaked os.epoch, filesystem, Lua load, and shell APIs. Run it with the CC:Tweaked Lua runtime.")
end

local programPath = shell.getRunningProgram()
local programDirectory = fs.getDir(programPath)
local baselinePath = fs.combine(programDirectory, "src/branch_miner.lua")

if not fs.exists(baselinePath) then
    error("oreMiner active baseline not found: " .. baselinePath)
end

-- Keep the runtime usable when a shell provides CC filesystem APIs but omits
-- Lua's module loader. Project modules use repository-relative dotted names.
if type(require) ~= "function" then
    local moduleCache = {}
    local loadingModules = {}

    local function loadModule(moduleName)
        if type(moduleName) ~= "string" or not moduleName:match("^[%w_%.]+$")
            or moduleName:sub(1, 1) == "." or moduleName:sub(-1) == "."
            or moduleName:find("..", 1, true) then
            error("invalid module name: " .. tostring(moduleName), 2)
        end
        if moduleCache[moduleName] ~= nil then return moduleCache[moduleName] end
        if loadingModules[moduleName] then
            error("circular module dependency: " .. moduleName, 2)
        end

        local relativePath = moduleName:gsub("%.", "/") .. ".lua"
        local modulePath = fs.combine(programDirectory, relativePath)
        local handle = fs.open(modulePath, "r")
        if not handle then error("module not found: " .. moduleName .. " (" .. modulePath .. ")", 2) end
        local source = handle.readAll()
        handle.close()
        if type(source) ~= "string" then error("unable to read module: " .. moduleName, 2) end

        loadingModules[moduleName] = true
        local environment = setmetatable({ require = loadModule }, { __index = _G })
        local chunk, compileError = load(source, "@" .. modulePath, "t", environment)
        if not chunk then
            loadingModules[moduleName] = nil
            error("unable to compile module " .. moduleName .. ": " .. tostring(compileError), 2)
        end
        local ok, result = pcall(chunk)
        loadingModules[moduleName] = nil
        if not ok then error("module " .. moduleName .. " failed: " .. tostring(result), 2) end
        if result == nil then result = true end
        moduleCache[moduleName] = result
        return result
    end

    require = loadModule
end

local baselineHandle = fs.open(baselinePath, "r")
if not baselineHandle then error("oreMiner cannot read active baseline: " .. baselinePath) end
local baselineSource = baselineHandle.readAll()
baselineHandle.close()
if type(baselineSource) ~= "string" then error("oreMiner active baseline is unreadable: " .. baselinePath) end
local baselineEnvironment = setmetatable({ require = require }, { __index = _G })
local baselineChunk, compileError = load(baselineSource, "@" .. baselinePath, "t", baselineEnvironment)
if not baselineChunk then error("oreMiner active baseline has invalid Lua syntax: " .. tostring(compileError)) end

local loaded, runtimeError = pcall(baselineChunk, ...)
if not loaded then
    local message = tostring(runtimeError)
    if message:find("global 'require'", 1, true) then
        error("oreMiner module loader failed: " .. message)
    end
    error("oreMiner active baseline failed: " .. message)
end
