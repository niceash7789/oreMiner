-- Decide whether a durable snapshot is safe to resume before any turtle action.
local Cursor = require("src.mining.cursor")
local RouteHome = require("src.navigation.route_home")
local FloorGrid = require("src.navigation.floor_grid")
local BranchTraversal = require("src.navigation.branch_traversal")
local BranchResume = require("src.mining.branch_resume")
local ActionStack = require("src.navigation.action_stack")

local Recovery = {}

local function samePose(left, right)
    return type(left) == "table" and type(right) == "table"
        and left.x == right.x and left.y == right.y
        and left.z == right.z and left.facing == right.facing
end

local function sameCursor(left, right)
    if not Cursor.validate(left) or not Cursor.validate(right) then return false end
    local fields = {
        "workDomain", "workUnitId", "floor", "stairSegment", "stairStep",
        "branchPair", "side", "mainSide", "phase", "offset", "mainOffset", "nextAction",
    }
    for _, field in ipairs(fields) do
        if left[field] ~= right[field] then return false end
    end
    return true
end

local function matchesJunctionPose(pose, landing, mainOffset, mainSide)
    if type(pose) ~= "table" or type(landing) ~= "table"
        or type(mainOffset) ~= "number" or mainOffset < 0 then
        return false
    end
    local facing = (landing.facing + (mainSide == "left" and 3 or 1)) % 4
    local x, z = landing.x, landing.z
    if facing == 0 then z = z - mainOffset
    elseif facing == 1 then x = x + mainOffset
    elseif facing == 2 then z = z + mainOffset
    else x = x - mainOffset end
    return pose.x == x and pose.y == landing.y and pose.z == z and pose.facing == facing
end

local function onMainReturn(pose, landing, mainOffset, mainSide)
    if type(pose) ~= "table" or type(landing) ~= "table"
        or type(mainOffset) ~= "number" or mainOffset < 0 then return false end
    local facing = (landing.facing + (mainSide == "left" and 3 or 1)) % 4
    local reverse = (facing + 2) % 4
    if pose.y ~= landing.y or (pose.facing ~= facing and pose.facing ~= reverse
        and not (samePose(pose, landing) and pose.facing == landing.facing)) then
        return false
    end
    for offset = 0, mainOffset do
        local cell = { x = pose.x, y = pose.y, z = pose.z, facing = facing }
        if matchesJunctionPose(cell, landing, offset, mainSide) then return true end
    end
    return false
end

function Recovery.classify(state, loadCode)
    if loadCode == "POSITION_UNCERTAIN" then
        return false, "POSITION_UNCERTAIN"
    end
    local recoverableServiceError = type(state) == "table" and state.status == "error"
        and state.service ~= nil and (state.error == "NO_SUPPLY_CHEST"
            or state.error == "NO_FUEL_SUPPLY" or state.error == "NO_TORCHES")
    if type(state) ~= "table" or (state.status ~= "mining" and state.status ~= "paused"
        and not recoverableServiceError)
        or state.poseCertainty ~= "known" or state.pendingAction ~= nil
        or not Cursor.validate(state.progress)
        or type(state.pose) ~= "table"
        or type(state.route) ~= "table" then
        return false, "RESUME_STATE_UNSAFE"
    end
    if state.vein ~= nil then
        local vein = state.vein
        local resume = state.resumeCheckpoint
        local checkpoint = vein.checkpoint
        local atCheckpoint = type(checkpoint) == "table" and samePose(state.pose, checkpoint)
        local activeAtKnownCell = vein.stage == "active" and not atCheckpoint
            and vein.visited[state.pose.x .. "," .. state.pose.y .. "," .. state.pose.z] == true
            and #vein.route == #vein.frontier and #vein.route == vein.blocks - 1
            and #vein.frontier > 0 and #vein.route > 0
        local atIntermediateUnwind = vein.stage == "unwinding" and not atCheckpoint
            and vein.visited[state.pose.x .. "," .. state.pose.y .. "," .. state.pose.z] == true
            and (#vein.route == 0 or #vein.frontier == #vein.route
                or #vein.frontier == #vein.route + 1)
        if vein.stage == "entering" or not resume or not sameCursor(resume.progress, state.progress)
            or (not atCheckpoint and not activeAtKnownCell and not atIntermediateUnwind)
            or (atCheckpoint and #vein.route ~= 0)
            or (vein.stage == "active" and #vein.frontier ~= #vein.route) then
            return false, "VEIN_RESUME_UNSUPPORTED"
        end
        local homePath = RouteHome.path(state.route, state.pose, nil,
            { x = 0, y = 0, z = 0, facing = 0 })
        if not homePath then
            return false, "HOME_ROUTE_UNAVAILABLE"
        end
        local cursorPose = { x = state.pose.x, y = state.pose.y,
            z = state.pose.z, facing = state.pose.facing }
        local unwindFacing = cursorPose.facing
        for index = #vein.route, 1, -1 do
            local breadcrumb = vein.route[index]
            local target = { x = cursorPose.x, y = cursorPose.y,
                z = cursorPose.z, facing = cursorPose.facing }
            local inverse = breadcrumb.inverse
            if inverse == "back" then
                if cursorPose.facing ~= breadcrumb.facing then
                    return false, "VEIN_RESUME_UNSUPPORTED"
                end
                target.facing = breadcrumb.facing
            elseif inverse ~= "up" and inverse ~= "down" then
                return false, "VEIN_RESUME_UNSUPPORTED"
            end
            if inverse == "up" then target.y = target.y + 1
            elseif inverse == "down" then target.y = target.y - 1
            elseif breadcrumb.facing == 0 then target.z = target.z + 1
            elseif breadcrumb.facing == 1 then target.x = target.x - 1
            elseif breadcrumb.facing == 2 then target.z = target.z - 1
            else target.x = target.x + 1 end
            local directionKnown = inverse == "up" and cursorPose.y > target.y
                or inverse == "down" and cursorPose.y < target.y
                or inverse == "back" and (math.abs(cursorPose.x - target.x)
                    + math.abs(cursorPose.z - target.z) == 1)
            if not directionKnown or not vein.visited[target.x .. "," .. target.y .. "," .. target.z]
                or not RouteHome.path(state.route, cursorPose, nil, target) then
                return false, "VEIN_RESUME_UNSUPPORTED"
            end
            cursorPose = target
            unwindFacing = breadcrumb.facing
        end
        if cursorPose.x ~= checkpoint.x or cursorPose.y ~= checkpoint.y
            or cursorPose.z ~= checkpoint.z or unwindFacing ~= checkpoint.facing then
            return false, "VEIN_RESUME_UNSUPPORTED"
        end

        -- The mining cursor describes the tunnel checkpoint. Once the saved
        -- breadcrumbs prove an exact unwind, classify that checkpoint rather
        -- than the turtle's committed position inside the vein.
        local checkpointState = {}
        for key, value in pairs(state) do checkpointState[key] = value end
        checkpointState.pose = checkpoint
        checkpointState.vein = nil
        return Recovery.classify(checkpointState, loadCode)
    end
    if state.routeStack ~= nil and not ActionStack.validate(state.routeStack) then
        return false, "ROUTE_STACK_INVALID"
    end
    if state.service ~= nil then
        local service = state.service
        local resume = state.resumeCheckpoint
        local origin = { x = 0, y = 0, z = 0, facing = 0 }
        if not resume or not resume.pose or not sameCursor(service.resumeProgress, state.progress)
            or not sameCursor(resume.progress, state.progress)
            or not samePose(service.checkpoint, origin)
                and not samePose(service.checkpoint, resume.pose) then
            return false, "SERVICE_RESUME_UNSUPPORTED"
        end
        if (service.stage == "at_base" or service.stage == "unloading")
            and (not samePose(state.pose, origin) or not samePose(service.checkpoint, origin)) then
            return false, "SERVICE_RESUME_UNSUPPORTED"
        end
        local homePath = RouteHome.path(state.route, state.pose, nil, origin)
        local targetPath = RouteHome.path(state.route, origin, nil, resume.pose)
        if not homePath or not targetPath then return false, "HOME_ROUTE_UNAVAILABLE" end

        -- Service may only return to a cursor whose executor is itself safe to
        -- dispatch. Classify that exact saved target as if service had cleared.
        local targetState = {}
        for key, value in pairs(state) do targetState[key] = value end
        targetState.pose = resume.pose
        targetState.service = nil
        if recoverableServiceError then
            targetState.status = "mining"
            targetState.error = nil
        end
        local targetAllowed, targetCode = Recovery.classify(targetState, loadCode)
        if not targetAllowed then return false, targetCode end
        return true, "RESUME_SAFE_SERVICE"
    end
    if state.progress.phase == "surface_entry" then
        local resume = state.resumeCheckpoint
        local origin = { x = 0, y = 0, z = 0, facing = 0 }
        if state.progress.nextAction ~= "enter_surface" or not resume or not resume.pose
            or not sameCursor(resume.progress, state.progress)
            or resume.pose.x ~= origin.x or resume.pose.y ~= origin.y
            or resume.pose.z ~= origin.z or resume.pose.facing ~= origin.facing
            or state.pose.x ~= origin.x or state.pose.y ~= origin.y
            or state.pose.z ~= origin.z or state.pose.facing ~= origin.facing
            or not samePose(state.pose, resume.pose) then
            return false, "SURFACE_ENTRY_RESUME_UNSUPPORTED"
        end

    elseif state.progress.phase == "main_side_start"
        or state.progress.phase == "main_side_return"
        or state.progress.phase == "main_shaft" or state.progress.phase == "junction" then
        local resume = state.resumeCheckpoint
        local landing = state.floorLandings and state.floorLandings[state.progress.floor]
        local savedConfig = state.configSnapshot
        local spacing = savedConfig and savedConfig.spacing
        if not resume or not resume.pose or not sameCursor(resume.progress, state.progress)
            or state.progress.floor < 1
            or type(spacing) ~= "number" or spacing < 1
            or (state.progress.phase == "main_side_start"
                and state.progress.nextAction ~= "turn_into_main")
            or (state.progress.phase == "main_side_return"
                and state.progress.nextAction ~= "return_to_landing")
            or (state.progress.phase == "main_shaft" and state.progress.nextAction ~= "mine_main_cell")
            or (state.progress.phase == "junction"
                and state.progress.nextAction ~= "turn_to_left_branch"
                and state.progress.nextAction ~= "restore_main_facing")
            or not landing or type(landing.landing) ~= "table"
            or (state.progress.phase ~= "main_side_start"
                and state.progress.phase ~= "main_side_return"
                and not samePose(state.pose, resume.pose)) then
            return false, state.progress.phase == "junction"
                and "JUNCTION_RESUME_UNSUPPORTED" or "MAIN_SHAFT_RESUME_UNSUPPORTED"
        end
        local mainSide = state.progress.mainSide or "right"
        if state.progress.phase == "main_side_start" then
            local startFacing = (landing.landing.facing
                + (mainSide == "left" and 3 or 1)) % 4
            if state.progress.branchPair ~= 1 or state.progress.mainOffset ~= 0
                or state.progress.offset ~= 0
                or state.pose.x ~= landing.landing.x
                or state.pose.y ~= landing.landing.y
                or state.pose.z ~= landing.landing.z
                or (state.pose.facing ~= landing.landing.facing
                    and state.pose.facing ~= startFacing)
                or not samePose(resume.pose, landing.landing) then
                return false, "MAIN_SIDE_START_RESUME_UNSUPPORTED"
            end
        elseif state.progress.phase == "main_side_return" then
            local savedCount = savedConfig and savedConfig.num_branches
            if type(savedCount) ~= "number" or savedCount < 1
                or state.progress.branchPair ~= savedCount
                or state.progress.mainOffset ~= savedCount * spacing
                or state.progress.offset ~= 0
                or not matchesJunctionPose(resume.pose, landing.landing,
                    state.progress.mainOffset, mainSide)
                or not onMainReturn(state.pose, landing.landing,
                    state.progress.mainOffset, mainSide)
                or not RouteHome.path(state.route, state.pose, nil, landing.landing) then
                return false, "MAIN_SIDE_RETURN_RESUME_UNSUPPORTED"
            end
        elseif state.progress.phase == "main_shaft" then
            local mainOffset = (state.progress.branchPair - 1) * spacing
            local cellOffset = mainOffset + state.progress.offset
            if state.progress.mainOffset ~= mainOffset or state.progress.offset >= spacing
                or not matchesJunctionPose(state.pose, landing.landing, cellOffset, mainSide) then
                return false, "MAIN_SHAFT_RESUME_UNSUPPORTED"
            end
        elseif state.progress.branchPair * spacing ~= state.progress.mainOffset
            or not matchesJunctionPose(state.pose, landing.landing,
                state.progress.mainOffset, mainSide) then
            return false, "JUNCTION_RESUME_UNSUPPORTED"
        end
        local homePath = RouteHome.path(state.route, state.pose, nil,
            { x = 0, y = 0, z = 0, facing = 0 })
        if not homePath then return false, "HOME_ROUTE_UNAVAILABLE" end

    elseif state.progress.phase == "branch_outbound_lower"
        or state.progress.phase == "branch_turnaround"
        or state.progress.phase == "branch_upper_return"
        or state.progress.phase == "branch_return_to_junction" then
        local resume = state.resumeCheckpoint
        local landing = state.floorLandings and state.floorLandings[state.progress.floor]
        local savedConfig = state.configSnapshot
        local start = BranchResume.start(state.progress, savedConfig and savedConfig.num_branches,
            savedConfig and savedConfig.spacing, savedConfig and savedConfig.branch_length)
        if not start or not landing or type(landing.landing) ~= "table"
            or not resume or not resume.pose or not sameCursor(resume.progress, state.progress)
            or not samePose(state.pose, resume.pose) then
            return false, "BRANCH_RESUME_UNSUPPORTED"
        end
        local grid, gridStatus = FloorGrid.new({ x = 0, y = 0, z = 0, facing = 0 }, 0,
            { floor = landing.floor, pose = landing.landing },
            savedConfig.stair_steps_per_floor,
            savedConfig.first_floor_depth_offset or 0)
        if not grid then return false, "BRANCH_RESUME_UNSUPPORTED" end
        local junction = grid.junction(state.progress.mainOffset,
            state.progress.mainSide or "right")
        local branch = grid.branch(junction, state.progress.side)
        local traversal = branch and BranchTraversal.new(branch, savedConfig.branch_length)
        local expected
        if traversal and state.progress.phase == "branch_outbound_lower" then
            expected = traversal.outboundPose(state.progress.offset)
        elseif traversal and state.progress.phase == "branch_turnaround" then
            expected = traversal.outboundPose(savedConfig.branch_length)
        elseif traversal and state.progress.phase == "branch_upper_return" then
            expected = traversal.upperReturnPose(savedConfig.branch_length - state.progress.offset)
        elseif traversal and state.progress.phase == "branch_return_to_junction" then
            expected = traversal.canonicalJunctionPose()
        end
        if not expected or not samePose(state.pose, expected) then
            return false, "BRANCH_RESUME_UNSUPPORTED"
        end
        local homePath = RouteHome.path(state.route, state.pose, nil,
            { x = 0, y = 0, z = 0, facing = 0 })
        if not homePath then return false, "HOME_ROUTE_UNAVAILABLE" end

    elseif state.progress.phase == "stairs" then
        if state.progress.nextAction ~= "cross_landing" then
            local stack = state.routeStack or { records = {} }
            if #stack.records > 0 then
                return false, "STAIR_ACTION_PENDING_UNSUPPORTED"
            end
            if state.progress.nextAction == "prepare_landing" then
                return false, "LANDING_CARVE_RESUME_UNSUPPORTED"
            end
            return false, "STAIR_SLICE_RESUME_UNSUPPORTED"
        end
        local floor = state.progress.floor
        local previous = state.floorLandings and state.floorLandings[floor - 1]
        local resume = state.resumeCheckpoint
        if floor <= 1 or not previous or type(previous.landing) ~= "table"
            or not resume or not resume.pose
            or not sameCursor(resume.progress, state.progress)
            or not samePose(resume.pose, state.pose)
            or not samePose(state.pose, previous.landing) then
            return false, "LANDING_RESUME_UNSUPPORTED"
        end
        if type(previous.floor) ~= "number" or previous.floor ~= floor - 1
            or type(previous.steps) ~= "number" or previous.steps < 1
            or previous.steps ~= math.floor(previous.steps)
            or (previous.entryMoves ~= 1 and previous.entryMoves ~= 4)
            or type(previous.mouth) ~= "table" or type(previous.rear) ~= "table"
            or type(previous.origin) ~= "table"
            or not RouteHome.path(state.route, state.pose, nil, origin) then
            return false, "LANDING_RESUME_UNSUPPORTED"
        end

    end
    if state.progress.phase == "floor_complete" then
        local landing = state.floorLandings and state.floorLandings[state.progress.floor]
        local resume = state.resumeCheckpoint
        if not landing or type(landing.landing) ~= "table"
            or not resume or not resume.pose
            or not sameCursor(resume.progress, state.progress)
            or resume.pose.x ~= state.pose.x or resume.pose.y ~= state.pose.y
            or resume.pose.z ~= state.pose.z or resume.pose.facing ~= state.pose.facing
            or landing.landing.x ~= state.pose.x or landing.landing.y ~= state.pose.y
            or landing.landing.z ~= state.pose.z or landing.landing.facing ~= state.pose.facing
            or not samePose(state.pose, resume.pose) then
            return false, "LANDING_RESUME_UNSUPPORTED"
        end
        local homePath = RouteHome.path(state.route, state.pose, nil,
            { x = 0, y = 0, z = 0, facing = 0 })
        if not homePath then return false, "HOME_ROUTE_UNAVAILABLE" end
    elseif state.progress.phase ~= "surface_entry" and state.progress.phase ~= "stairs"
        and state.progress.phase ~= "main_side_start"
        and state.progress.phase ~= "main_side_return"
        and state.progress.phase ~= "main_shaft" and state.progress.phase ~= "junction"
        and state.progress.phase ~= "branch_outbound_lower"
        and state.progress.phase ~= "branch_turnaround"
        and state.progress.phase ~= "branch_upper_return"
        and state.progress.phase ~= "branch_return_to_junction" then
        -- Do not travel to a cursor whose next work unit cannot be dispatched.
        return false, "CURSOR_RESUME_UNSUPPORTED"
    end
    return true, "RESUME_SAFE_CHECKPOINT"
end

return Recovery

