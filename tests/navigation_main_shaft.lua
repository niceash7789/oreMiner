local MainShaft = require("src.navigation.main_shaft")

for facing = 0, 3 do
    local landing = { x = -2, y = -8, z = 7, facing = facing }
    for _, side in ipairs({ "right", "left" }) do
        local mainFacing = (facing + (side == "right" and 1 or 3)) % 4
        local shaft = assert(MainShaft.new(landing, mainFacing, 10))
        local start = assert(shaft.pose(0))
        assert(start.x == landing.x and start.y == landing.y and start.z == landing.z
            and start.facing == mainFacing, "both main shafts start at the landing centre")
        local finish = assert(shaft.pose(10))
        local deltaX, deltaZ = finish.x - start.x, finish.z - start.z
        if mainFacing == 0 then assert(deltaZ == -10 and deltaX == 0)
        elseif mainFacing == 1 then assert(deltaX == 10 and deltaZ == 0)
        elseif mainFacing == 2 then assert(deltaZ == 10 and deltaX == 0)
        else assert(deltaX == -10 and deltaZ == 0) end
        assert(shaft.isCanonicalReturn(start), "exact return reaches the landing centre")
        assert(not shaft.isCanonicalReturn(finish), "endpoint is not the landing centre")
    end
end

local _, reason = MainShaft.new({ x = 0, y = 0, z = 0, facing = 0 }, 2, 4)
assert(reason.code == "INVALID_MAIN_SHAFT_ORIGIN", "a main shaft must be perpendicular")
local shaft = assert(MainShaft.new({ x = 0, y = -8, z = -12, facing = 0 }, 1, 4))
local _, invalidOffset = shaft.pose(5)
assert(invalidOffset.code == "INVALID_MAIN_SHAFT_OFFSET")

print("navigation main-shaft checks passed")
