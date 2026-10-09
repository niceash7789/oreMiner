-- Compose the fixed surface entry and repeated stair slices into one
-- checkpointed floor route. Physical actions remain owned by checked callers.
local Contracts = require("src.core.contracts")
local Pose = require("src.navigation.pose")
local SurfaceEntry = require("src.navigation.surface_entry")
local StairSlice = require("src.navigation.stair_slice")
local Result = require("src.safety.result")

local StairRoute = {}

local function copyPose(pose)
    return { x = pose.x, y = pose.y, z = pose.z, facing = pose.facing }
end

local function samePose(left, right)
    return Contracts.isPose(left) and Contracts.isPose(right)
        and left.x == right.x and left.y == right.y
        and left.z == right.z and left.facing == right.facing
end

local function forwardPose(pose, count)
    local result = copyPose(pose)
    for _ = 1, count do result = assert(Pose.afterMove(result, "forward", true)) end
    return result
end

local function fail(pose, code, message, extra)
    return pose, Result.new(false, code, message, extra)
end

local function validate(options)
    return type(options) == "table"
        and Contracts.isPose(options.pose)
        and type(options.floor) == "number" and options.floor >= 1
        and options.floor == math.floor(options.floor)
        and type(options.steps) == "number" and options.steps >= 1
        and options.steps == math.floor(options.steps)
        and (options.floor == 1 or options.alreadyAtFrontLanding == true)
        and type(options.move) == "function"
        and type(options.turn) == "function"
        and type(options.clear) == "function"
        and type(options.prepareLanding) == "function"
        and type(options.saveLanding) == "function"
end

-- Descend from the surface for floor 1, or from the prior landing's front
-- centre for later floors. prepareLanding owns the plan-defined flat 3x3 carve
-- and must finish one forward block beyond the last slice (landing centre).
function StairRoute.descend(options)
    if not validate(options) then
        return type(options) == "table" and options.pose or nil,
            Result.new(false, "INVALID_STAIR_ROUTE_OPTIONS")
    end

    local start = copyPose(options.pose)
    local current = start
    if options.floor == 1 then
        local outcome
        current, outcome = SurfaceEntry.enter({ pose = current, move = options.move })
        if outcome.ok ~= true then return current, outcome end
    end

    local mouth = copyPose(current)
    if options.floor > 1 then
        local moved, moveOutcome = options.move("forward")
        local expected = forwardPose(current, 1)
        if not Contracts.isResult(moveOutcome) or moveOutcome.ok ~= true
            or not samePose(moved, expected) then
            return Contracts.isPose(moved) and moved or current,
                Result.new(false, "LANDING_CROSSING_FAILED",
                    "Could not cross the recorded front-centre landing cell.", {
                        floor = options.floor,
                    })
        end
        current = copyPose(moved)
        mouth = copyPose(current)
    end

    for step = 1, options.steps do
        local outcome
        current, outcome = StairSlice.descend({
            pose = current,
            clear = options.clear,
            move = options.move,
            turn = options.turn,
        })
        if outcome.ok ~= true then
            return current, Result.new(false, outcome.code or "STAIR_DESCENT_FAILED",
                outcome.message, { floor = options.floor, step = step })
        end
        if options.saveProgress then
            local saved, saveOutcome = options.saveProgress({
                floor = options.floor,
                stairStep = step,
                pose = copyPose(current),
            })
            if saved ~= true then
                return current, Contracts.isResult(saveOutcome) and saveOutcome
                    or Result.new(false, "STATE_WRITE_FAILED",
                        "Could not persist stair progress.", { floor = options.floor, step = step })
            end
        end
    end

    local rear = copyPose(current)
    local landingPose, landingOutcome = options.prepareLanding(copyPose(rear), options.floor)
    local expectedLanding = forwardPose(rear, 1)
    if not Contracts.isResult(landingOutcome) or landingOutcome.ok ~= true
        or not samePose(landingPose, expectedLanding) then
        return Contracts.isPose(landingPose) and landingPose or rear,
            Result.new(false, "LANDING_INVALID",
                "Landing preparation must finish at the centre cell one block beyond the recorded rear cell.", {
                    floor = options.floor,
                })
    end

    local route = {
        floor = options.floor,
        origin = copyPose(start),
        mouth = copyPose(mouth),
        rear = copyPose(rear),
        landing = copyPose(landingPose),
        steps = options.steps,
        entryMoves = options.floor == 1 and SurfaceEntry.LENGTH or 1,
    }
    local saved, saveOutcome = options.saveLanding(route)
    if saved ~= true then
        return copyPose(landingPose), Contracts.isResult(saveOutcome) and saveOutcome
            or Result.new(false, "STATE_WRITE_FAILED", "Could not persist the floor landing.")
    end
    return copyPose(landingPose), Result.new(true, "LANDING_RECORDED", nil, route)
end

-- Return only over the route captured by descend(). The recorded poses are
-- checked after each inverse operation; this path never digs or chooses a shortcut.
function StairRoute.returnToSurface(options)
    if type(options) ~= "table" or not Contracts.isPose(options.pose)
        or type(options.route) ~= "table" or not Contracts.isPose(options.route.origin)
        or not Contracts.isPose(options.route.rear) or not Contracts.isPose(options.route.landing)
        or type(options.route.steps) ~= "number" or options.route.steps < 1
        or options.route.steps ~= math.floor(options.route.steps)
        or (options.route.entryMoves ~= SurfaceEntry.LENGTH and options.route.entryMoves ~= 1)
        or not Contracts.isPose(options.route.mouth)
        or type(options.move) ~= "function" or type(options.turn) ~= "function" then
        return type(options) == "table" and options.pose or nil,
            Result.new(false, "INVALID_STAIR_ROUTE_OPTIONS")
    end

    local route = options.route
    local current = copyPose(options.pose)
    if not samePose(current, route.landing) then
        return current, Result.new(false, "POSITION_ERROR", "Return must start at the saved landing centre.")
    end

    local moved, outcome = options.move("back")
    if not Contracts.isResult(outcome) or outcome.ok ~= true
        or not samePose(moved, route.rear) then
        return Contracts.isPose(moved) and moved or current,
            Result.new(false, "LANDING_RETURN_FAILED", "Could not return to the recorded landing rear cell.")
    end
    current = copyPose(moved)

    for step = route.steps, 1, -1 do
        local expectedUp = assert(Pose.afterMove(current, "up", true))
        local expected = assert(Pose.afterMove(expectedUp, "back", true))
        local climbed, climbOutcome = StairSlice.climb({
            pose = current,
            move = options.move,
            turn = options.turn,
        })
        if climbOutcome.ok ~= true then return climbed, climbOutcome end
        if not samePose(climbed, expected) then
            return Contracts.isPose(climbed) and climbed or current,
                Result.new(false, "POSITION_ERROR", "Stair climb did not reach the previous recorded centreline pose.", {
                    step = step,
                })
        end
        current = copyPose(climbed)
    end

    if route.entryMoves == SurfaceEntry.LENGTH then
        local returned, returnOutcome = SurfaceEntry.returnToOrigin({
            pose = current,
            origin = route.origin,
            move = options.move,
        })
        if returnOutcome.ok ~= true then return returned, returnOutcome end
        current = copyPose(returned)
    else
        local returned, returnOutcome = options.move("back")
        if not Contracts.isResult(returnOutcome) or returnOutcome.ok ~= true
            or not samePose(returned, route.origin) then
            return Contracts.isPose(returned) and returned or current,
                Result.new(false, "LANDING_RETURN_FAILED", "Could not return to the previous landing centre.")
        end
        current = copyPose(returned)
    end
    if not samePose(current, route.origin) then
        return current, Result.new(false, "POSITION_ERROR", "Recorded route did not restore its origin pose.")
    end
    return current, Result.new(true, "SURFACE_ORIGIN_RESTORED")
end

return StairRoute
