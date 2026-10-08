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

return OreClassifier
