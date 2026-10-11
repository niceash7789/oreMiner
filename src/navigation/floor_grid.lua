-- Geometry for a floor grid anchored to one recorded staircase landing.
local FloorGrid = {}
local StairGeometry = require("src.core.stair_geometry")

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
function FloorGrid.new(origin, staircaseFacing, landing, stairStepsPerFloor, firstFloorDepthOffset)
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
    firstFloorDepthOffset = firstFloorDepthOffset or 0
    if not StairGeometry.stepsForFloor(stairStepsPerFloor,
        firstFloorDepthOffset, landing.floor) then
        return nil, failure("INVALID_STAIR_STEPS", "A validated stair interval is required.")
    end

    local expected = copyPose(origin)
    expected.y = origin.y - landing.floor * stairStepsPerFloor - firstFloorDepthOffset
    -- Floor one has four entry moves, the configured slices, and one centre move.
    -- Each later segment crosses the prior landing, adds configured slices, then
    -- moves from stair rear-centre to the new landing centre.
    expected = step(expected, staircaseFacing,
        3 + landing.floor * (stairStepsPerFloor + 2) + firstFloorDepthOffset)
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

    function grid.mainFacingFor(mainSide)
        if mainSide ~= "right" and mainSide ~= "left" then
            return nil, failure("INVALID_MAIN_SIDE", "Main shaft side must be left or right.")
        end
        return turn(staircaseFacing, mainSide), { ok = true, code = "MAIN_FACING" }
    end

    function grid.junction(mainOffset, mainSide)
        if not isInteger(mainOffset) or mainOffset < 0 then
            return nil, failure("INVALID_MAIN_OFFSET", "Main-tunnel offset must be a non-negative integer.")
        end
        local facing, status = grid.mainFacingFor(mainSide or "right")
        if not facing then return nil, status end
        return step(grid.landing.pose, facing, mainOffset), { ok = true, code = "JUNCTION_POSE" }
    end

    function grid.branch(junctionPose, side)
        if side ~= "left" and side ~= "right" then
            return nil, failure("INVALID_BRANCH_SIDE", "Branch side must be left or right.")
        end
        local rightFacing = grid.mainFacing
        local leftFacing = turn(staircaseFacing, "left")
        if not validPose(junctionPose) or junctionPose.y ~= grid.landing.pose.y
            or (junctionPose.facing ~= rightFacing and junctionPose.facing ~= leftFacing) then
            return nil, failure("INVALID_JUNCTION", "Branch must start at a lower-level junction facing along this floor's main tunnel.")
        end
        local branchFacing = turn(junctionPose.facing, side)
        local branchOrigin = copyPose(junctionPose)
        branchOrigin.facing = branchFacing
        return {
            side = side,
            origin = branchOrigin,
            facing = branchFacing,
            junctionFacing = junctionPose.facing,
        },
            { ok = true, code = "BRANCH_GRID_CREATED" }
    end

    return grid, { ok = true, code = "FLOOR_GRID_CREATED" }
end

return FloorGrid
