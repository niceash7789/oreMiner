local OreClassifier = require("src.mining.ore_classifier")
local defaults = require("src.config.defaults")

local function ore(block, config)
    return OreClassifier.isOre(block, config)
end

assert(ore({ name = "minecraft:iron_ore" }, defaults.ore), "suffix fallback should classify common ores")
assert(ore({ name = "example:deep_crystal", tags = { ["c:ores"] = true } }, defaults.ore),
    "inspect tags should classify modded resources")
assert(not ore({ name = "example:deep_crystal" }, defaults.ore), "unknown IDs without positive evidence must fail closed")
assert(not ore({ name = "example:ore_polished_block" }, defaults.ore), "suffix matching must not accept an inner ore token")

local custom = {
    mode = "all",
    names = { "example:custom_resource" },
    tags = { "example:valuable" },
    namePatterns = {},
    ignoreNames = { "example:custom_resource" },
    ignoreTags = { "example:ignored" },
}
assert(not ore({ name = "example:custom_resource" }, custom), "ignore ID must override explicit include")
assert(ore({ name = "example:other_resource", tags = { ["example:valuable"] = true } }, custom))
assert(not ore({ name = "example:other_resource", tags = { ["example:ignored"] = true } }, custom),
    "ignore tag must override positive tag")

local whitelist = {
    mode = "whitelist",
    names = { "example:listed" },
    tags = { "example:listed_tag" },
    namePatterns = { "_ore$" },
}
assert(ore({ name = "example:listed" }, whitelist))
assert(ore({ name = "example:tagged", tags = { ["example:listed_tag"] = true } }, whitelist))
assert(not ore({ name = "minecraft:iron_ore" }, whitelist), "whitelist must ignore fallback patterns")

local blacklist = {
    mode = "blacklist",
    names = { "example:known_ore" },
    tags = { "example:ore_tag" },
    namePatterns = { "_ore$" },
    ignoreNames = { "example:blocked_ore" },
    ignoreTags = { "example:blocked_tag" },
}
assert(ore({ name = "example:known_ore" }, blacklist), "blacklist mode must accept positively classified names")
assert(ore({ name = "example:tagged", tags = { ["example:ore_tag"] = true } }, blacklist),
    "blacklist mode must accept positively classified tags")
assert(ore({ name = "example:modded_ore" }, blacklist), "blacklist mode must accept configured ore patterns")
assert(not ore({ name = "example:blocked_ore" }, blacklist), "blacklist mode must reject explicitly ignored names")
assert(not ore({ name = "example:other", tags = { ["example:blocked_tag"] = true } }, blacklist),
    "blacklist mode must reject explicitly ignored tags")
assert(not ore({ name = "example:unclassified" }, blacklist),
    "blacklist mode must require positive ore evidence")

local valuable = { mode = "valuable", valuableNames = { "example:diamond_like" }, tags = {}, ignoreNames = {}, ignoreTags = {} }
assert(ore({ name = "example:diamond_like" }, valuable))
assert(not ore({ name = "minecraft:iron_ore" }, valuable))

assert(not ore(nil, defaults.ore), "missing inspect data must be rejected")
assert(not ore(false, defaults.ore), "invalid inspect data must be rejected")
assert(not ore({ tags = { ["c:ores"] = true } }, defaults.ore), "missing block name must be rejected")
assert(not ore({ name = "example:unknown", tags = "c:ores" }, defaults.ore), "invalid tags must be rejected")
assert(not ore({ name = "example:unknown" }, nil), "missing config must be rejected")

local missing = OreClassifier.missingConfiguredTags({
    tags = { "c:ores", "mod:missing" },
    ignoreTags = { "mod:ignored", "mod:missing" },
    availableTagKeys = { "c:ores", "mod:ignored" },
})
assert(#missing == 1 and missing[1] == "mod:missing",
    "authoritative tag registry should produce deduplicated warnings")
assert(#OreClassifier.missingConfiguredTags(defaults.ore) == 0,
    "absence of a registry must not produce speculative missing-tag warnings")

print("ore classifier tests passed")
