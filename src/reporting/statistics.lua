local Statistics = {}

function Statistics.new(initial)
    local values = {}
    for key, value in pairs(initial or {}) do
        if type(key) == "string" and type(value) == "number" then
            values[key] = value
        end
    end

    local stats = {}
    function stats:add(key, amount)
        local ok = pcall(function()
            if type(key) ~= "string" or type(amount) ~= "number" then return end
            values[key] = (values[key] or 0) + amount
        end)
        return ok
    end
    function stats:get(key)
        local ok, value = pcall(function() return values[key] or 0 end)
        if ok and type(value) == "number" then return value end
        return 0
    end
    function stats:snapshot()
        local copy = {}
        local ok = pcall(function()
            for key, value in pairs(values) do copy[key] = value end
        end)
        if not ok then return {} end
        return copy
    end
    return stats
end

function Statistics.jobSummary(stats, options)
    options = options or {}
    local get = type(stats) == "table" and stats.get or nil
    local function value(key)
        if type(get) ~= "function" then return 0 end
        local ok, result = pcall(get, stats, key)
        if ok and type(result) == "number" then return result end
        return 0
    end
    local blocks = value("blocks_mined")
    local fuel = value("fuel_used")
    local started = options.startedAt
    local ended = options.endedAt
    local runtime = 0
    if type(started) == "number" and type(ended) == "number" and ended >= started then
        runtime = ended - started
    end
    return {
        blocksDug = blocks,
        oreBlocksDug = value("ores_mined"),
        veinsStarted = value("veins_found"),
        fuelUsed = fuel,
        serviceTrips = value("service_trips"),
        branchPairsCompleted = value("branches_completed"),
        stairSlicesCompleted = value("stair_slices_completed"),
        floorsCompleted = value("floors_completed"),
        torchesPlaced = value("torches_placed"),
        activeRuntime = runtime,
        orePerFuel = fuel > 0 and value("ores_mined") / fuel or 0,
        orePerTunnel = value("tunnel_blocks_mined") > 0
            and value("ores_mined") / value("tunnel_blocks_mined") or 0,
        orePerActiveHour = runtime > 0
            and value("ores_mined") * 3600 / runtime or 0,
        oreByType = type(stats) == "table" and type(stats.snapshot) == "function"
            and stats:snapshot() or {},
    }
end

function Statistics.formatJobSummary(summary)
    summary = summary or {}
    local lines = {
        string.format("Job summary: %d branch pairs",
            summary.branchPairsCompleted or 0),
        string.format("Blocks dug: %d (%d ore); veins: %d",
            summary.blocksDug or 0, summary.oreBlocksDug or 0, summary.veinsStarted or 0),
        string.format("Fuel: %d; service trips: %d",
            summary.fuelUsed or 0, summary.serviceTrips or 0),
        string.format("Active: %.1fs; ore/fuel: %.2f; ore/hour: %.2f",
            summary.activeRuntime or 0, summary.orePerFuel or 0, summary.orePerActiveHour or 0),
    }
    return lines
end

function Statistics.addAll(stats, amounts)
    if type(stats) ~= "table" or type(stats.add) ~= "function"
        or type(amounts) ~= "table" then return false end
    local ok = true
    for key, amount in pairs(amounts) do
        local added, result = pcall(stats.add, stats, key, amount)
        if not added or result ~= true then ok = false end
    end
    return ok
end

function Statistics.addOreCounts(stats, block, amount)
    if type(block) ~= "table" or type(block.name) ~= "string"
        or type(amount) ~= "number" then return false end
    return Statistics.addAll(stats, { ["ore_type:" .. block.name] = amount })
end

return Statistics

