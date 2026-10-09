local VeinTraversal = require("src.mining.vein_traversal")

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
        reportCap = function(blocks, maxBlocks, maxRadius)
            capReports[#capReports + 1] = { blocks = blocks, maxBlocks = maxBlocks, maxRadius = maxRadius }
        end,
    }
    local checkpoint = { x = 0, y = 0, z = 0, facing = 0 }
    local result = VeinTraversal.run(checkpoint, api, "back", function(block)
        return block.qualified == true
    end)
    return result, pose, capReports
end

-- A branching, cyclic vein visits each cell once and unwinds to the exact pose.
local result, pose = run({ ["0,0,-2"] = { qualified = true } })
assert(result.ok and result.blocks == 2 and result.code == "VEIN_COMPLETE")
assert(pose.x == 0 and pose.y == 0 and pose.z == 0 and pose.facing == 0)

-- Pressure abort unwinds the current breadcrumb stack.
result, pose = run({ ["0,0,-2"] = { qualified = true } }, { pressure = true })
assert(result.ok and result.code == "INVENTORY_RETURN" and pose.z == 0 and pose.facing == 0)

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
        if not pressureChecked then pressureChecked = true; return true end
        return false
    end,
}
local pressureResult = VeinTraversal.run({ x = 0, y = 0, z = 0, facing = 0 }, pressureOps,
    "back", function(block) return block and block.qualified end)
assert(pressureResult.ok and pressureResult.code == "INVENTORY_RETURN")
assert(discoveryCalls == 0, "unwind request at the seed must suppress further neighbor discovery")

print("vein traversal checks passed")









