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
    return stats
end

return Statistics
