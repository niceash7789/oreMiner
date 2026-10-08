-- Floor-relative poses for a two-level branch excursion.
local BranchTraversal = {}

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

local function step(pose, distance)
    local result = copyPose(pose)
    if pose.facing == 0 then
        result.z = result.z - distance
    elseif pose.facing == 1 then
        result.x = result.x + distance
    elseif pose.facing == 2 then
        result.z = result.z + distance
    else
        result.x = result.x - distance
    end
    return result
end

local function validFacing(value)
    return isInteger(value) and value >= 0 and value <= 3
end

-- Produces poses only; callers perform and verify movement before committing them.
function BranchTraversal.new(branch, length)
    if type(branch) ~= "table" or not validPose(branch.origin)
        or not validFacing(branch.facing) or branch.origin.facing ~= branch.facing
        or not validFacing(branch.junctionFacing) then
        return nil, failure("INVALID_BRANCH", "A branch origin, heading, and junction facing are required.")
    end
    if not isInteger(length) or length < 1 then
        return nil, failure("INVALID_LENGTH", "Branch length must be a positive integer.")
    end

    local lowerOrigin = copyPose(branch.origin)
    local upperOrigin = copyPose(branch.origin)
    upperOrigin.y = upperOrigin.y + 1

    local traversal = {
        length = length,
        branchFacing = branch.facing,
        junctionFacing = branch.junctionFacing,
        lowerJunction = copyPose(lowerOrigin),
        upperJunction = copyPose(upperOrigin),
    }
    traversal.lowerJunction.facing = branch.junctionFacing
    traversal.upperJunction.facing = branch.junctionFacing

    function traversal.outboundPose(distance)
        if not isInteger(distance) or distance < 0 or distance > traversal.length then
            return nil, failure("INVALID_OUTBOUND_DISTANCE", "Outbound distance must be within the branch length.")
        end
        local pose = step(lowerOrigin, distance)
        pose.facing = traversal.branchFacing
        return pose, { ok = true, code = "LOWER_OUTBOUND_POSE" }
    end

    -- returnDistance is measured from the far endpoint toward the junction.
    function traversal.upperReturnPose(returnDistance)
        if not isInteger(returnDistance) or returnDistance < 0 or returnDistance > traversal.length then
            return nil, failure("INVALID_RETURN_DISTANCE", "Return distance must be within the branch length.")
        end
        local pose = step(upperOrigin, traversal.length - returnDistance)
        pose.y = upperOrigin.y
        pose.facing = (traversal.branchFacing + 2) % 4
        return pose, { ok = true, code = "UPPER_RETURN_SCAN_POSE" }
    end

    function traversal.canonicalJunctionPose()
        return copyPose(traversal.lowerJunction), { ok = true, code = "BRANCH_RETURNED_TO_JUNCTION" }
    end

    return traversal, { ok = true, code = "BRANCH_TRAVERSAL_CREATED" }
end

return BranchTraversal
