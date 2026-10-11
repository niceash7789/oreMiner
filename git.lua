-- Read-only oreMiner pull client for CC:Tweaked.
-- Derived from tekytek/ccgit (MIT), reduced to one safe foreground pull.

local arguments = { ... }
local GITHUB_API = "https://api.github.com/repos/"
local GITHUB_RAW = "https://raw.githubusercontent.com/"
local STAGING_NAME = ".oreminer-pull"
local BACKUP_NAME = ".oreminer-pull-backup"

local function reportError(message)
    if type(printError) == "function" then
        printError(message)
    else
        print(message)
    end
end

local function combine(root, path)
    if root == "" then return path end
    return fs.combine(root, path)
end

local function readFile(path)
    local handle = fs.open(path, "r")
    if not handle then return nil end
    local contents = handle.readAll()
    handle.close()
    return contents
end

local function writeFile(path, contents)
    local parent = fs.getDir(path)
    if parent ~= "" and not fs.exists(parent) then fs.makeDir(parent) end
    local handle = fs.open(path, "w")
    if not handle then error("Unable to write " .. path, 0) end
    handle.write(contents)
    handle.close()
end

local function findRepository()
    local path = shell.dir()
    while true do
        local configPath = combine(path, ".git_config")
        if fs.exists(configPath) then return path, configPath end
        if path == "" then break end
        local parent = fs.getDir(path)
        if parent == path then break end
        path = parent
    end
    return nil, nil
end

local function loadRepository(configPath)
    local raw = readFile(configPath)
    if not raw then return nil, "Unable to read .git_config" end
    local ok, repository = pcall(textutils.unserialize, raw)
    if not ok or type(repository) ~= "table"
        or type(repository.repo) ~= "string"
        or not repository.repo:match("^[%w_.-]+/[%w_.-]+$")
        or type(repository.branch) ~= "string"
        or not repository.branch:match("^[%w%._/-]+$") then
        return nil, "Invalid .git_config"
    end
    return repository
end

local function saveRepository(configPath, repository)
    writeFile(configPath, textutils.serialize(repository))
end

local function request(url)
    local response, reason = http.get(url, {
        ["Accept"] = "application/vnd.github+json",
        ["User-Agent"] = "oreMiner-CCGit",
        ["X-GitHub-Api-Version"] = "2022-11-28",
    })
    if not response then return nil, reason or "HTTP request failed" end
    local code = response.getResponseCode and response.getResponseCode() or 200
    local body = response.readAll()
    response.close()
    if code ~= 200 then return nil, "GitHub returned HTTP " .. tostring(code) end
    local ok, value = pcall(textutils.unserializeJSON, body)
    if not ok or type(value) ~= "table" then return nil, "GitHub returned invalid JSON" end
    return value
end

local function download(url)
    local response, reason = http.get(url, { ["User-Agent"] = "oreMiner-CCGit" })
    if not response then return nil, reason or "download failed" end
    local code = response.getResponseCode and response.getResponseCode() or 200
    local contents = response.readAll()
    response.close()
    if code ~= 200 then return nil, "download returned HTTP " .. tostring(code) end
    if contents == nil or contents == "" then return nil, "download was empty" end
    return contents
end

local function safePath(path)
    if type(path) ~= "string" or path == "" or path:sub(1, 1) == "/"
        or path:find("\\", 1, true) then return false end
    for part in path:gmatch("[^/]+") do
        if part == "." or part == ".." or part == "" then return false end
    end
    return true
end

local function managedPath(path)
    return path == "miner.lua"
        or path == "boot.lua"
        or path == "install.lua"
        or path == "git.lua"
        or path == "config.example.lua"
        or path:match("^src/.+%.lua$") ~= nil
end

local function selectFiles(tree)
    if tree.truncated then return nil, "GitHub tree response was truncated" end
    if type(tree.tree) ~= "table" then return nil, "GitHub tree response is invalid" end
    local files = {}
    local required = {}
    for _, item in ipairs(tree.tree) do
        if item.type == "blob" and managedPath(item.path) then
            if not safePath(item.path) then return nil, "Unsafe repository path: " .. tostring(item.path) end
            files[#files + 1] = item.path
            required[item.path] = true
        end
    end
    table.sort(files)
    for _, path in ipairs({ "miner.lua", "boot.lua", "install.lua", "git.lua", "config.example.lua" }) do
        if not required[path] then return nil, "Repository is missing " .. path end
    end
    if #files < 6 then return nil, "Repository contains no runtime modules" end
    return files
end

local function syntaxCheck(path, contents)
    local chunk, reason = load(contents, "@" .. path, "t", {})
    if not chunk then return false, reason end
    return true
end

local function stageFiles(root, repository, commitSha, files)
    local staging = combine(root, STAGING_NAME)
    if fs.exists(staging) then fs.delete(staging) end
    fs.makeDir(staging)
    for index, path in ipairs(files) do
        print(string.format("[%d/%d] %s", index, #files, path))
        local url = GITHUB_RAW .. repository.repo .. "/" .. commitSha .. "/" .. path
        local contents, reason = download(url)
        if not contents then
            fs.delete(staging)
            return nil, "Unable to download " .. path .. ": " .. tostring(reason)
        end
        local valid, syntaxError = syntaxCheck(path, contents)
        if not valid then
            fs.delete(staging)
            return nil, "Downloaded Lua is invalid at " .. path .. ": " .. tostring(syntaxError)
        end
        writeFile(combine(staging, path), contents)
    end
    return staging
end

local function restore(root, backup, records)
    for index = #records, 1, -1 do
        local record = records[index]
        local target = combine(root, record.path)
        local saved = combine(backup, record.path)
        if fs.exists(target) then fs.delete(target) end
        if record.hadOld and fs.exists(saved) then
            local parent = fs.getDir(target)
            if parent ~= "" and not fs.exists(parent) then fs.makeDir(parent) end
            fs.move(saved, target)
        end
    end
end

local function installStaged(root, staging, files, previousFiles)
    local backup = combine(root, BACKUP_NAME)
    if fs.exists(backup) then fs.delete(backup) end
    fs.makeDir(backup)

    local wanted = {}
    for _, path in ipairs(files) do wanted[path] = true end
    local changes = {}
    for _, path in ipairs(previousFiles or {}) do
        if managedPath(path) and safePath(path) and not wanted[path] then
            changes[#changes + 1] = path
        end
    end
    for _, path in ipairs(files) do changes[#changes + 1] = path end

    local records = {}
    local ok, reason = pcall(function()
        for _, path in ipairs(changes) do
            local target = combine(root, path)
            local saved = combine(backup, path)
            local hadOld = fs.exists(target)
            if hadOld then
                local parent = fs.getDir(saved)
                if parent ~= "" and not fs.exists(parent) then fs.makeDir(parent) end
                fs.move(target, saved)
            end
            records[#records + 1] = { path = path, hadOld = hadOld }
            if wanted[path] then
                local staged = combine(staging, path)
                local parent = fs.getDir(target)
                if parent ~= "" and not fs.exists(parent) then fs.makeDir(parent) end
                fs.move(staged, target)
            end
        end
    end)

    if not ok then
        restore(root, backup, records)
        if fs.exists(staging) then fs.delete(staging) end
        if fs.exists(backup) then fs.delete(backup) end
        return false, "Install failed and was rolled back: " .. tostring(reason)
    end
    fs.delete(staging)
    fs.delete(backup)
    return true
end

local function createLiveConfig(root)
    local live = combine(root, "config.lua")
    if fs.exists(live) then
        print("Keeping existing config.lua")
        return true
    end
    local example = combine(root, "config.example.lua")
    local contents = readFile(example)
    if not contents then return false, "Installed config.example.lua is missing" end
    writeFile(live, contents)
    print("Created config.lua from config.example.lua")
    return true
end

local function ensureAutostart(root)
    local startupDirectory = "/startup"
    local hookPath = fs.combine(startupDirectory, "oreminer.lua")
    local marker = "-- oreMiner managed startup hook\n"
    local program = "/" .. combine(root, "boot.lua"):gsub("^/", "")
    if not fs.exists(combine(root, "boot.lua")) then
        return false, "boot.lua is missing; pull the current runtime first"
    end
    local contents = marker .. "shell.run(" .. string.format("%q", program) .. ")\n"
    if fs.exists(hookPath) then
        local existing = readFile(hookPath)
        if existing == contents then return true end
        if type(existing) ~= "string" or existing:sub(1, #marker) ~= marker then
            return false, "Existing /startup/oreminer.lua was preserved; install the oreMiner hook manually"
        end
        fs.delete(hookPath)
    end
    if not fs.exists(startupDirectory) then fs.makeDir(startupDirectory) end
    writeFile(hookPath, contents)
    return true
end

local function pull()
    if type(http) ~= "table" or type(http.get) ~= "function" then
        return false, "HTTP is disabled in CC:Tweaked"
    end
    local root, configPath = findRepository()
    if not root then return false, "Not in an oreMiner repository (.git_config missing)" end
    local repository, configError = loadRepository(configPath)
    if not repository then return false, configError end
    print("Checking " .. repository.repo .. " (" .. repository.branch .. ")...")
    local commit, commitError = request(GITHUB_API .. repository.repo
        .. "/commits/" .. repository.branch)
    if not commit then return false, commitError end
    local commitSha = commit.sha
    local treeSha = commit.commit and commit.commit.tree and commit.commit.tree.sha
    if type(commitSha) ~= "string" or not commitSha:match("^[0-9a-fA-F]+$")
        or type(treeSha) ~= "string" or not treeSha:match("^[0-9a-fA-F]+$") then
        return false, "GitHub commit response is incomplete"
    end
    if repository.commit == commitSha and fs.exists(combine(root, "boot.lua")) then
        local hooked, hookResult, hookError = pcall(ensureAutostart, root)
        if not hooked then
            print("Autostart setup failed: " .. tostring(hookResult))
        elseif not hookResult then
            print("Autostart setup failed: " .. tostring(hookError))
        end
        print("Already up to date at " .. commitSha:sub(1, 7))
        return true
    end

    local tree, treeError = request(GITHUB_API .. repository.repo
        .. "/git/trees/" .. treeSha .. "?recursive=1")
    if not tree then return false, treeError end
    local files, fileError = selectFiles(tree)
    if not files then return false, fileError end

    print("Pulling " .. commitSha:sub(1, 7) .. "...")
    local staging, stageError = stageFiles(root, repository, commitSha, files)
    if not staging then return false, stageError end
    local installed, installError = installStaged(root, staging, files, repository.files)
    if not installed then return false, installError end
    local configured, configurationError = createLiveConfig(root)
    if not configured then return false, configurationError end

    repository.commit = commitSha
    repository.files = files
    saveRepository(configPath, repository)
    local hooked, hookResult, hookError = pcall(ensureAutostart, root)
    if not hooked then
        print("Autostart setup failed: " .. tostring(hookResult))
    elseif not hookResult then
        print("Autostart setup failed: " .. tostring(hookError))
    end
    print("Pull complete at " .. commitSha:sub(1, 7))
    return true
end

if arguments[1] ~= "pull" or arguments[2] ~= nil then
    print("Usage: git pull")
    return
end

local ok, reason = pull()
if not ok then
    reportError("git pull failed: " .. tostring(reason))
    error(reason, 0)
end

