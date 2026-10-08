local Backfill = require("src.mining.main_shaft_backfill")

local function run(direction, options)
    options = options or {}
    local pose = { x = 2, y = -8, z = -15, facing = 1 }
    local checkpoint = { x = 2, y = -8, z = -15, facing = 1 }
    local placed, inspected = {}, {}
    local ops = {
        pose = function() return pose end,
        turnRight = function() pose.facing = (pose.facing + 1) % 4 return true end,
        turnLeft = function() pose.facing = (pose.facing + 3) % 4 return true end,
        selectCobblestone = function() return options.noCobble ~= true end,
        place = function(target)
            placed[#placed + 1] = target
            return options.placeResult ~= false
        end,
        inspect = function(target)
            inspected[#inspected + 1] = target
            return true,
                { name = options.wrongBlock and "minecraft:stone" or "minecraft:cobblestone" }
        end,
    }
    local result = Backfill.seal(checkpoint, direction, ops)
    return result, pose, placed, inspected
end

for _, direction in ipairs({ "forward", "up", "down" }) do
    local result, pose, placed, inspected = run(direction)
    assert(result.ok and result.code == "BACKFILL_SEALED")
    assert(#placed == 1 and placed[1] == direction, "only exposed shaft face is placed")
    assert(#inspected == 1 and inspected[1] == direction, "placement is inspected")
    assert(pose.x == 2 and pose.y == -8 and pose.z == -15 and pose.facing == 1,
        "checkpoint pose and facing are preserved")
end

local result, _, placed = run("forward", { noCobble = true })
assert(not result.ok and result.code == "BACKFILL_COBBLESTONE_UNAVAILABLE" and #placed == 0)
result, _, placed = run("down", { placeResult = false })
assert(not result.ok and result.code == "BACKFILL_PLACE_FAILED" and #placed == 1)
result = run("up", { wrongBlock = true })
assert(not result.ok and result.code == "BACKFILL_VERIFY_FAILED")
result = run("left")
assert(not result.ok and result.code == "BACKFILL_INVALID_DIRECTION")

print("main shaft backfill checks passed")
