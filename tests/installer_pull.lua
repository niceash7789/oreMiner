local function memoryFs(initialFiles)
    local files = {}
    local directories = { [""] = true }

    local function normalize(path)
        path = tostring(path or ""):gsub("\\", "/"):gsub("^/+", ""):gsub("/+$", "")
        path = path:gsub("/+", "/")
        return path
    end

    local function getDir(path)
        path = normalize(path)
        return path:match("^(.*)/[^/]+$") or ""
    end

    local function makeDir(path)
        path = normalize(path)
        local parent = getDir(path)
        if parent ~= path and not directories[parent] then makeDir(parent) end
        directories[path] = true
    end

    for path, contents in pairs(initialFiles or {}) do
        path = normalize(path)
        makeDir(getDir(path))
        files[path] = contents
    end

    local api = {}
    function api.combine(left, right)
        left, right = normalize(left), normalize(right)
        if left == "" then return right end
        if right == "" then return left end
        return left .. "/" .. right
    end
    api.getDir = getDir
    function api.exists(path)
        path = normalize(path)
        return files[path] ~= nil or directories[path] == true
    end
    api.makeDir = makeDir
    function api.open(path, mode)
        path = normalize(path)
        if mode == "r" then
            if files[path] == nil then return nil end
            return { readAll = function() return files[path] end, close = function() end }
        end
        if mode ~= "w" then error("unsupported mode " .. tostring(mode)) end
        local buffer = ""
        return {
            write = function(value) buffer = buffer .. tostring(value) end,
            close = function()
                makeDir(getDir(path))
                files[path] = buffer
            end,
        }
    end
    function api.delete(path)
        path = normalize(path)
        files[path] = nil
        for candidate in pairs(files) do
            if candidate:sub(1, #path + 1) == path .. "/" then files[candidate] = nil end
        end
        for candidate in pairs(directories) do
            if candidate == path or candidate:sub(1, #path + 1) == path .. "/" then
                directories[candidate] = nil
            end
        end
    end
    function api.move(from, to)
        from, to = normalize(from), normalize(to)
        if files[from] ~= nil then
            if files[to] ~= nil or directories[to] then error("destination exists: " .. to) end
            makeDir(getDir(to))
            files[to], files[from] = files[from], nil
            return
        end
        if not directories[from] then error("source missing: " .. from) end
        makeDir(to)
        local movedFiles = {}
        for candidate, contents in pairs(files) do
            if candidate:sub(1, #from + 1) == from .. "/" then
                movedFiles[to .. candidate:sub(#from + 1)] = contents
                files[candidate] = nil
            end
        end
        for candidate, contents in pairs(movedFiles) do files[candidate] = contents end
        api.delete(from)
    end
    return api, files
end

local function response(body)
    return {
        getResponseCode = function() return 200 end,
        readAll = function() return body end,
        close = function() end,
    }
end

local function runPull(stateStatus)
    local stateBody = stateStatus and "STATE" or nil
    local fsApi, files = memoryFs({
        ["oreMiner/.git_config"] = "CONFIG",
        ["oreMiner/config.lua"] = "LOCAL CONFIG",
        ["oreMiner/miner.lua"] = "OLD MINER",
        ["oreMiner/src/old.lua"] = "OLD MODULE",
        ["oreMiner/oreMiner/state.json"] = stateBody,
    })
    if not stateStatus then files["oreMiner/oreMiner/state.json"] = nil end

    local repository = {
        repo = "niceash7789/oreMiner",
        branch = "main",
        commit = "aaaaaaa",
        files = { "miner.lua", "src/old.lua" },
    }
    local savedRepository
    local httpCalls = 0
    local environment = setmetatable({
        fs = fsApi,
        shell = { dir = function() return "oreMiner" end },
        http = {
            get = function(url)
                httpCalls = httpCalls + 1
                if url:find("/commits/main", 1, true) then return response("COMMIT") end
                if url:find("/git/trees/ccccccc", 1, true) then return response("TREE") end
                if url:find("raw.githubusercontent.com", 1, true) then
                    local path = url:match("/bbbbbbb/(.+)$")
                    return response("return " .. string.format("%q", path))
                end
                error("unexpected URL: " .. url)
            end,
        },
        textutils = {
            unserialize = function(raw)
                if raw == "CONFIG" then return repository end
                if raw == "STATE" then
                    if stateStatus == "unreadable" then error("invalid saved state") end
                    return { status = stateStatus }
                end
                if raw == "SAVED_CONFIG" then return savedRepository end
                error("unexpected serialized value")
            end,
            serialize = function(value)
                savedRepository = value
                return "SAVED_CONFIG"
            end,
            unserializeJSON = function(raw)
                if raw == "COMMIT" then
                    return { sha = "bbbbbbb", commit = { tree = { sha = "ccccccc" } } }
                end
                if raw == "TREE" then
                    return {
                        truncated = false,
                        tree = {
                            { type = "blob", path = "miner.lua" },
                            { type = "blob", path = "install.lua" },
                            { type = "blob", path = "git.lua" },
                            { type = "blob", path = "config.example.lua" },
                            { type = "blob", path = "src/new.lua" },
                            { type = "blob", path = "tests/not-installed.lua" },
                        },
                    }
                end
                error("unexpected JSON")
            end,
        },
        print = function() end,
        printError = function() end,
    }, { __index = _G })
    local chunk = assert(loadfile("git.lua", "t", environment))
    local ok, reason = pcall(chunk, "pull")
    return ok, reason, files, savedRepository, httpCalls
end

local ok, reason, files, savedRepository = runPull("complete")
assert(ok, reason)
assert(files["oreMiner/config.lua"] == "LOCAL CONFIG", "pull must preserve live config")
assert(files["oreMiner/oreMiner/state.json"] == "STATE", "pull must preserve saved state")
assert(files["oreMiner/src/old.lua"] == nil, "pull should remove stale managed files")
assert(files["oreMiner/src/new.lua"] == 'return "src/new.lua"', "pull should install runtime modules")
assert(files["oreMiner/tests/not-installed.lua"] == nil, "pull must exclude development files")
assert(files["oreMiner/config.example.lua"] ~= nil, "pull should install the tracked example")
assert(savedRepository.commit == "bbbbbbb" and #savedRepository.files == 5,
    "pull should persist the installed commit and managed file list")

ok, reason, files, savedRepository, httpCalls = runPull("mining")
assert(ok, reason)
assert(httpCalls > 0, "saved run state must not block network access")
assert(files["oreMiner/oreMiner/state.json"] == "STATE", "pull must preserve incomplete saved state")
assert(files["oreMiner/src/new.lua"] == 'return "src/new.lua"',
    "pull must install runtime modules with incomplete saved state")

ok, reason, files = runPull("unreadable")
assert(ok, reason)
assert(files["oreMiner/oreMiner/state.json"] == "STATE",
    "pull must preserve saved state without requiring a valid status")

local fsApi, bootstrapFiles = memoryFs({})
local ranClient
local bootstrapEnvironment = setmetatable({
    fs = fsApi,
    shell = {
        dir = function() return "" end,
        run = function(path, command)
            ranClient = { path, command }
            return true
        end,
    },
    http = { get = function() return response("return true") end },
    textutils = {
        serialize = function() return "BOOTSTRAP_CONFIG" end,
        unserialize = function() return nil end,
    },
    print = function() end,
    printError = function() end,
}, { __index = _G })
local bootstrap = assert(loadfile("install.lua", "t", bootstrapEnvironment))
ok, reason = pcall(bootstrap)
assert(ok, reason)
assert(ranClient and ranClient[1] == ".oreminer-bootstrap-git" and ranClient[2] == "pull",
    "installer should perform exactly one foreground pull")
assert(bootstrapFiles[".git_config"] == "BOOTSTRAP_CONFIG",
    "installer should initialize the repository metadata")
assert(bootstrapFiles[".oreminer-bootstrap-git"] == nil,
    "installer should remove its temporary pull client")

print("installer and single-pull checks passed")
