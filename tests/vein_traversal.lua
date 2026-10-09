local VeinTraversal = require("src.mining.vein_traversal")
local InventoryPressure = require("src.inventory.pressure")
local InventoryDefaults = require("src.config.defaults")

local recoveryPose = { x = 0, y = 0, z = -2, facing = 0 }
local recoveredStates = {}
local savedVein = {
    stage = "active", checkpoint = { x = 0, y = 0, z = 0, facing = 0 },
    visited = { ["0,0,0"] = true, ["0,0,-1"] = true, ["0,0,-2"] = true },
    frontier = { { next = 2, rotateOnReturn = false }, { next = 1, rotateOnReturn = true } },
    route = { { inverse = "back", facing = 0 }, { inverse = "back", facing = 0 } },
    blocks = 3,
}
local recovered = VeinTraversal.unwindSaved(savedVein, {
    pose = function() return recoveryPose end,
    turn = function(direction)
        if direction ~= "right" then return false end
        recoveryPose.facing = (recoveryPose.facing + 1) % 4
        return true
    end,
    move = function(direction)
        if direction ~= "back" then return false end
        recoveryPose.z = recoveryPose.z + 1
        return true
    end,
}, function(state)
    recoveredStates[#recoveredStates + 1] = state
    return true
end)
assert(recovered.ok and recoveryPose.z == 0 and recoveryPose.facing == 0,
    "reboot recovery must unwind each saved inverse to the original checkpoint pose")
assert(recoveredStates[1].stage == "unwinding" and recoveredStates[2].stage == "unwinding"
    and recoveredStates[3] == nil
    and #recoveredStates[1].route == 2 and #recoveredStates[2].route == 1,
    "persist valid remaining inverse routes and clear at the final checkpoint")

local blockedPose = { x = 0, y = 0, z = -2, facing = 0 }
local blockedRecovery = VeinTraversal.unwindSaved(savedVein, {
    pose = function() return blockedPose end,
    turn = function() return true end,
    move = function() return false end,
}, function() return true end)
assert(not blockedRecovery.ok and blockedRecovery.code == "VEIN_RETURN_BLOCKED"
    and blockedPose.z == -2,
    "failed recovery inverse must stop without claiming checkpoint arrival")

-- Inject failure at each position in a mixed inverse route. Earlier edges may
-- commit, but the failed edge remains recorded and no later inverse is tried.
local inverseDirections = { "back", "down", "up", "back" }
for failAt = 1, #inverseDirections do
    local calls, moved = 0, 0
    local pose = { x = 0, y = 0, z = -2, facing = 0 }
    local route = {}
    for index, direction in ipairs(inverseDirections) do
        route[index] = { inverse = direction, facing = 0 }
    end
    local states = {}
    local failed = VeinTraversal.unwindSaved({
        stage = "unwinding",
        checkpoint = { x = 0, y = 0, z = 0, facing = 0 },
        visited = { ["0,0,0"] = true }, frontier = {}, route = route, blocks = 5,
    }, {
        pose = function() return pose end,
        turn = function() return true end,
        move = function(direction)
            calls = calls + 1
            if calls == failAt then return false end
            moved = moved + 1
            return true
        end,
    }, function(state)
        states[#states + 1] = state
        return true
    end)
    assert(not failed.ok and failed.code == "VEIN_RETURN_BLOCKED",
        "every inverse edge failure must be fatal")
    assert(calls == failAt and moved == failAt - 1,
        "unwind must stop immediately at the injected failed edge")
    assert(#states[#states].route == #inverseDirections - failAt + 1,
        "failed edge and all later edges must remain durably recorded")
end

local intermediatePose = { x = 0, y = 0, z = -1, facing = 0 }
local intermediateSaves = {}
local intermediate = {
    stage = "unwinding", checkpoint = { x = 0, y = 0, z = 0, facing = 0 },
    visited = { ["0,0,0"] = true, ["0,0,-1"] = true, ["0,0,-2"] = true },
    frontier = { { next = 7, rotateOnReturn = true } },
    route = { { inverse = "back", facing = 0 } }, blocks = 3,
}
local intermediateResult = VeinTraversal.unwindSaved(intermediate, {
    pose = function() return intermediatePose end,
    turn = function() return true end,
    move = function(direction)
        if direction ~= "back" then return false end
        intermediatePose.z = intermediatePose.z + 1
        return true
    end,
}, function(state)
    intermediateSaves[#intermediateSaves + 1] = state
    return true
end)
assert(intermediateResult.ok and intermediatePose.z == 0
    and intermediateSaves[1].stage == "unwinding"
    and #intermediateSaves[1].route == 1 and #intermediateSaves[1].frontier == 1
    and intermediateSaves[2] == nil,
    "recovery persists only schema-valid intermediate routes and clears at the final checkpoint")

local function run(world, opts)
    local pose = { x = 0, y = 0, z = -1, facing = 0 }
    local function target(direction)
        local result = { x = pose.x, y = pose.y, z = pose.z, facing = pose.facing }
        if direction == "up" then result.y = result.y + 1
        elseif direction == "down" then result.y = result.y - 1
        else
            local sign = direction == "back" and -1 or 1
            if pose.facing == 0 then result.z = result.z - sign
            elseif pose.facing == 1 then result.x = result.x + sign
            elseif pose.facing == 2 then result.z = result.z + sign
            else result.x = result.x - sign end
        end
        return result
    end
    local function key(p) return p.x .. "," .. p.y .. "," .. p.z end
    local capReports = {}
    local api = {
        pose = function() return pose end,
        project = function(direction) return target(direction) end,
        inspect = function(direction)
            local ore = world[key(target(direction))]
            return ore ~= nil, ore
        end,
        dig = function(direction)
            local nextKey = key(target(direction))
            if not world[nextKey] or world[nextKey].qualified ~= true then return false end
            world[nextKey] = nil
            return true
        end,
        move = function(direction)
            if opts and opts.failInverse == direction then return false end
            if opts and opts.failOutward == direction then return false end
            pose = target(direction)
            return true
        end,
        turnRight = function() pose.facing = (pose.facing + 1) % 4 return true end,
        inventoryPressure = function() return opts and opts.pressure == true end,
        canContinue = function()
            return not (opts and opts.denyFuel == true)
        end,
        reportCap = function(blocks, maxBlocks, maxRadius)
            capReports[#capReports + 1] = { blocks = blocks, maxBlocks = maxBlocks, maxRadius = maxRadius }
        end,
    }
    local checkpoint = { x = 0, y = 0, z = 0, facing = 0 }
    local savedStates = {}
    local clearedState = false
    local result = VeinTraversal.run(checkpoint, api, "back", function(block)
        return block.qualified == true
    end, nil, function(state)
        if state == nil then
            clearedState = true
            return true
        end
        savedStates[#savedStates + 1] = state
        return not (opts and opts.failStateSaveAt == #savedStates)
    end)
    return result, pose, capReports, savedStates, clearedState
end

-- A branching, cyclic vein visits each cell once and unwinds to the exact pose.
local result, pose = run({ ["0,0,-2"] = { qualified = true } })
assert(result.ok and result.blocks == 2 and result.code == "VEIN_COMPLETE")
assert(pose.x == 0 and pose.y == 0 and pose.z == 0 and pose.facing == 0)

local durableResult, durablePose, _, durableStates, clearedDurableState = run({
    ["0,0,-2"] = { qualified = true },
})
assert(durableResult.ok and clearedDurableState,
    "completed traversal should persist its frontier then clear the excursion record")
assert(durableStates[1].stage == "active" and durableStates[1].blocks == 1
    and #durableStates[1].route == 1,
    "seed entry should begin with a durable inverse breadcrumb")
local sawChild, sawUnwind = false, false
for _, saved in ipairs(durableStates) do
    if saved.blocks == 2 and #saved.route == 2 then sawChild = true end
    if saved.stage == "unwinding" then sawUnwind = true end
end
assert(sawChild and sawUnwind and durablePose.z == 0,
    "successful edges and the transition to exact unwind should be persisted")

local failedSaveResult = run({ ["0,0,-2"] = { qualified = true } }, { failStateSaveAt = 2 })
assert(not failedSaveResult.ok and failedSaveResult.code == "VEIN_STATE_WRITE_FAILED",
    "a failed durable frontier write must stop the excursion")

-- Pressure abort unwinds the current breadcrumb stack.
result, pose = run({ ["0,0,-2"] = { qualified = true } }, { pressure = true })
assert(result.ok and result.code == "INVENTORY_RETURN" and pose.z == 0 and pose.facing == 0)

-- Fuel denial unwinds before another dig or move and returns a distinct reason.
local fuelWorld = { ["0,0,-2"] = { qualified = true } }
result, pose = run(fuelWorld, { denyFuel = true })
assert(result.ok and result.code == "VEIN_FUEL_RETURN"
    and pose.z == 0 and pose.facing == 0,
    "denied route fuel must unwind to the exact checkpoint")
assert(fuelWorld["0,0,-2"] ~= nil,
    "fuel denial must happen before digging a newly discovered block")

-- A failed inverse is fatal and is never reported as a successful return.
result = run({ ["0,0,-2"] = { qualified = true } }, { failInverse = "back" })
assert(not result.ok and result.code == "VEIN_RETURN_BLOCKED")

-- Vertical breadcrumbs must fail closed when their inverse up/down move fails.
result = run({ ["0,1,-1"] = { qualified = true } }, { failInverse = "down" })
assert(not result.ok and result.code == "VEIN_RETURN_BLOCKED")
result = run({ ["0,-1,-1"] = { qualified = true } }, { failInverse = "up" })
assert(not result.ok and result.code == "VEIN_RETURN_BLOCKED")

-- A failed outward move leaves the caller with an explicit fatal outcome.
result = run({ ["0,0,-2"] = { qualified = true } }, { failOutward = "forward" })
assert(not result.ok and result.code == "VEIN_MOVE_FAILED")

local longVein = {}
for distance = 2, 12 do
    longVein["0,0,-" .. distance] = { qualified = true }
end
local capReports
result, pose, capReports = run(longVein)
assert(result.ok and result.code == "VEIN_CAP_REACHED" and result.blocks == 8)
assert(pose.z == 0 and pose.facing == 0, "capped DFS must still unwind to its checkpoint")
assert(#capReports == 1 and capReports[1].blocks == 8
    and capReports[1].maxBlocks == 64 and capReports[1].maxRadius == 8,
    "cap exhaustion must be reported after successful unwind")

-- A failed cap unwind must not report exhaustion or claim the tunnel can continue.
result, pose, capReports = run(longVein, { failInverse = "back" })
assert(not result.ok and result.code == "VEIN_RETURN_BLOCKED")
assert(#capReports == 0, "failed unwind must suppress cap report and tunnel continuation")

-- Classification, rather than equality to the seed ID, defines vein membership.
local mixedVein = {
    ["0,0,-2"] = { qualified = true, id = "mod:iron_ore" },
    ["0,0,-3"] = { qualified = true, id = "other:copper_ore" },
    ["0,0,-4"] = { qualified = false, id = "minecraft:stone" },
}
result, pose = run(mixedVein)
assert(result.ok and result.blocks == 3 and result.code == "VEIN_COMPLETE")
assert(mixedVein["0,0,-4"] ~= nil, "non-ore boundary must not be dug")
assert(pose.z == 0 and pose.facing == 0, "mixed-ID vein must unwind to checkpoint")

-- Pressure at the seed checkpoint must unwind immediately without probing or digging neighbors.
local discoveryCalls = 0
local pressureWorld = {
    ["0,0,-2"] = { qualified = true },
}
local pressurePose = { x = 0, y = 0, z = -1, facing = 0 }
local pressureChecked = false
local pressureSlots = {}
for slot = 1, InventoryDefaults.inventory.returnThreshold do pressureSlots[slot] = 1 end
local pressureInventory = { getItemCount = function(slot) return pressureSlots[slot] or 0 end }
local pressureOps = {
    pose = function() return pressurePose end,
    project = function(direction)
        if direction == "up" then return { x = pressurePose.x, y = pressurePose.y + 1, z = pressurePose.z }
        elseif direction == "down" then return { x = pressurePose.x, y = pressurePose.y - 1, z = pressurePose.z } end
        return { x = pressurePose.x, y = pressurePose.y, z = pressurePose.z - 1 }
    end,
    inspect = function() discoveryCalls = discoveryCalls + 1; return false end,
    dig = function() error("pressure must prevent digging") end,
    move = function(direction)
        if direction == "back" then pressurePose.z = pressurePose.z + 1; return true end
        error("pressure must prevent outward movement")
    end,
    turnRight = function() pressurePose.facing = (pressurePose.facing + 1) % 4; return true end,
    inventoryPressure = function() return false end,
    beforeDiscover = function()
        pressureChecked = true
        local reached = InventoryPressure.reached(
            pressureInventory, InventoryDefaults.inventory.returnThreshold)
        return reached
    end,
}
local pressureResult = VeinTraversal.run({ x = 0, y = 0, z = 0, facing = 0 }, pressureOps,
    "back", function(block) return block and block.qualified end)
assert(pressureResult.ok and pressureResult.code == "INVENTORY_RETURN")
assert(pressureChecked, "the configured pressure probe must run before vein discovery")
assert(discoveryCalls == 0, "unwind request at the seed must suppress further neighbor discovery")

print("vein traversal checks passed")









