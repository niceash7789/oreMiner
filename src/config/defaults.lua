-- Item-ID classifications retained from the phase-one reference miner.
return {
    inventory = {
        pressureThreshold = 14,
        fuelRetainedCount = 64,
        torchRetainedCount = 64,
        retainedItems = {
            ["minecraft:cobblestone"] = 64, -- mandatory main-shaft backfill reserve
        },
        protectedItems = {},
    },
    safety = {
        moveRetries = 5,
        digRetries = 12,
        digTimeLimit = 5,
        entityRetries = 5,
        retryDelay = 0.4,
    },
    fuel = {
        allowedItems = {
            "minecraft:coal",
            "minecraft:charcoal",
            "minecraft:coal_block",
        },
    },
    paving = {
        enabled = false,
        protectedItems = {},
        allowedItems = {
            "minecraft:cobblestone",
            "minecraft:cobbled_deepslate",
            "minecraft:dirt",
            "minecraft:netherrack",
        },
    },
    base = {
        acceptedChestBlockIds = {
            "minecraft:chest",
            "minecraft:trapped_chest",
        },
    },
    ore = {
        mode = "all",
        names = {},
        tags = { "c:ores", "forge:ores" },
        namePatterns = { "_ore$" },
        ignoreNames = {},
        ignoreTags = {},
        valuableNames = {},
    },
}
