-- Geometry for a floor grid anchored to one recorded staircase landing.
local FloorGrid = {}

local function isInteger(value)
    return type(value) == "number" and value == math.floor(value)
end

local function validPose(pose)
    return type(pose) == "table"
        and isInteger(pose.x)
        and isInteger(pose.y)
        and isInteger(pose.z)
        and isInteger(pose.facing)
        and pose.facing >= 0
        and pose.facing <= 3
end

local function failure(code, message)
    return { ok = false, code = code, message = message, retryable = false }
end

local function copyPose(pose)
    return { x = pose.x, y = pose.y, z = pose.z, facing = pose.facing }
end

local function step(pose, facing, distance)
    local result = copyPose(pose)
    if facing == 0 then
        result.z = result.z - distance
    elseif facing == 1 then
        result.x = result.x + distance
    elseif facing == 2 then
        result.z = result.z + distance
    else
        result.x = result.x - distance
    end
    result.facing = facing
    return result
end

local function turn(facing, side)
    local delta = side == "right" and 1 or -1
    return (facing + delta) % 4
end

-- Requires the landing record; no floor coordinates are inferred from surface origin.
function FloorGrid.new(origin, staircaseFacing, landing)
    if not validPose(origin) then
        return nil, failure("INVALID_ORIGIN", "Surface origin must be a valid pose.")
    end
    if staircaseFacing ~= origin.facing then
        return nil, failure("ORIGIN_FACING_MISMATCH", "Staircase facing must match the fixed surface-origin facing.")
    end
    if type(landing) ~= "table" or not isInteger(landing.floor) or landing.floor < 1
        or not validPose(landing.pose) then
        return nil, failure("INVALID_LANDING", "A floor number and recorded landing pose are required.")
    end

    local expected = copyPose(origin)
    expected.y = origin.y - landing.floor * 8
    expected = step(expected, staircaseFacing, 4 + landing.floor * 8)
    if landing.pose.x ~= expected.x or landing.pose.y ~= expected.y
        or landing.pose.z ~= expected.z or landing.pose.facing ~= staircaseFacing then
        return nil, failure("LANDING_MISMATCH", "Recorded landing does not match the fixed V1 origin and stair geometry.")
    end

    local grid = {
        origin = copyPose(origin),
        staircaseFacing = staircaseFacing,
        landing = { floor = landing.floor, pose = copyPose(landing.pose) },
        mainFacing = turn(staircaseFacing, "right"),
    }

    function grid.junction(mainOffset)
        if not isInteger(mainOffset) or mainOffset < 0 then
            return nil, failure("INVALID_MAIN_OFFSET", "Main-tunnel offset must be a non-negative integer.")
        end
        return step(grid.landing.pose, grid.mainFacing, mainOffset), { ok = true, code = "JUNCTION_POSE" }
    end

    function grid.branch(junctionPose, side)
        if side ~= "left" and side ~= "right" then
            return nil, failure("INVALID_BRANCH_SIDE", "Branch side must be left or right.")
        end
        if not validPose(junctionPose) or junctionPose.y ~= grid.landing.pose.y
            or junctionPose.facing ~= grid.mainFacing then
            return nil, failure("INVALID_JUNCTION", "Branch must start at a lower-level junction facing along this floor's main tunnel.")
        end
        local branchFacing = turn(grid.mainFacing, side)
        local branchOrigin = copyPose(junctionPose)
        branchOrigin.facing = branchFacing
        return {
            side = side,
            origin = branchOrigin,
            facing = branchFacing,
            junctionFacing = grid.mainFacing,
        },
            { ok = true, code = "BRANCH_GRID_CREATED" }
    end

    return grid, { ok = true, code = "FLOOR_GRID_CREATED" }
end

return FloorGrid
