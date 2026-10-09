local OreClassifier = {}

local function contains(values, value)
    if type(values) ~= "table" or type(value) ~= "string" then
        return false
    end
    for _, candidate in ipairs(values) do
        if candidate == value then
            return true
        end
    end
    return false
end

local function hasTag(tags, candidates)
    if type(tags) ~= "table" or type(candidates) ~= "table" then
        return false
    end
    for _, tag in ipairs(candidates) do
        if type(tag) == "string" and (tags[tag] == true or contains(tags, tag)) then
            return true
        end
    end
    return false
end

local function matchesPattern(name, patterns)
    if type(name) ~= "string" or type(patterns) ~= "table" then
        return false
    end
    for _, pattern in ipairs(patterns) do
        if type(pattern) == "string" then
            local ok, matched = pcall(string.find, name, pattern)
            if ok and matched then
                return true
            end
        end
    end
    return false
end

function OreClassifier.isOre(block, config)
    if type(block) ~= "table" or type(block.name) ~= "string" or block.name == "" then
        return false
    end
    if type(config) ~= "table" then
        return false
    end

    local ignored = contains(config.ignoreNames, block.name)
        or hasTag(block.tags, config.ignoreTags)
    if ignored then
        return false
    end

    if config.mode == "whitelist" then
        return contains(config.names, block.name) or hasTag(block.tags, config.tags)
    elseif config.mode == "valuable" then
        return contains(config.valuableNames, block.name)
    end

    -- `all` and `blacklist` use positive tags/names plus configured fallback patterns.
    return contains(config.names, block.name)
        or hasTag(block.tags, config.tags)
        or matchesPattern(block.name, config.namePatterns)
end

-- CC:Tweaked exposes tags only on inspected blocks, not a global registry.
-- Use an explicitly supplied authoritative list when one is available and do
-- not infer missing tags from the blocks encountered so far.
function OreClassifier.missingConfiguredTags(config)
    if type(config) ~= "table" or type(config.availableTagKeys) ~= "table" then
        return {}
    end
    local available = {}
    for _, tag in ipairs(config.availableTagKeys) do
        if type(tag) == "string" then available[tag] = true end
    end
    local missing, seen = {}, {}
    for _, configured in ipairs({ config.tags, config.ignoreTags }) do
        if type(configured) == "table" then
            for _, tag in ipairs(configured) do
                if type(tag) == "string" and not available[tag] and not seen[tag] then
                    seen[tag] = true
                    missing[#missing + 1] = tag
                end
            end
        end
    end
    table.sort(missing)
    return missing
end

return OreClassifier
