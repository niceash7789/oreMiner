-- One-command oreMiner bootstrap for CC:Tweaked.
-- Downloads the repository's read-only git client, then performs one pull.

local REPOSITORY = "niceash7789/oreMiner"
local BRANCH = "main"
local CLIENT_URL = "https://raw.githubusercontent.com/"
    .. REPOSITORY .. "/" .. BRANCH .. "/git.lua"

local function fail(message)
    if type(printError) == "function" then printError(message) else print(message) end
    error(message, 0)
end

if type(http) ~= "table" or type(http.get) ~= "function" then
    fail("HTTP is disabled in CC:Tweaked")
end
if type(fs) ~= "table" or type(shell) ~= "table" then
    fail("The CC:Tweaked filesystem and shell APIs are required")
end

local root = shell.dir()
local temporaryClient = fs.combine(root, ".oreminer-bootstrap-git")
local configPath = fs.combine(root, ".git_config")

local response, reason = http.get(CLIENT_URL, { ["User-Agent"] = "oreMiner-Installer" })
if not response then fail("Unable to download the pull client: " .. tostring(reason)) end
local code = response.getResponseCode and response.getResponseCode() or 200
local client = response.readAll()
response.close()
if code ~= 200 then fail("Pull client download returned HTTP " .. tostring(code)) end
if not client or client == "" then fail("Pull client download was empty") end
local chunk, syntaxError = load(client, "@git.lua", "t", {})
if not chunk then fail("Downloaded pull client is invalid: " .. tostring(syntaxError)) end

local handle = fs.open(temporaryClient, "w")
if not handle then fail("Unable to stage the pull client") end
handle.write(client)
handle.close()

if fs.exists(configPath) then
    local existingHandle = fs.open(configPath, "r")
    local raw = existingHandle and existingHandle.readAll() or nil
    if existingHandle then existingHandle.close() end
    local ok, existing = pcall(textutils.unserialize, raw or "")
    if not ok or type(existing) ~= "table" or existing.repo ~= REPOSITORY
        or existing.branch ~= BRANCH then
        fs.delete(temporaryClient)
        fail("Existing .git_config belongs to another repository or branch")
    end
else
    local configHandle = fs.open(configPath, "w")
    if not configHandle then
        fs.delete(temporaryClient)
        fail("Unable to create .git_config")
    end
    configHandle.write(textutils.serialize({ repo = REPOSITORY, branch = BRANCH }))
    configHandle.close()
end

print("Installing oreMiner with one foreground pull...")
local pulled = shell.run(temporaryClient, "pull")
if fs.exists(temporaryClient) then fs.delete(temporaryClient) end
if not pulled then fail("oreMiner pull failed; existing live files were preserved") end

print("")
print("oreMiner installed successfully.")
print("Edit config.lua, then run: miner")
print("To fetch a later test build, stop the miner and run: git pull")

