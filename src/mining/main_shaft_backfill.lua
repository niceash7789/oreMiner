-- Seals only the exposed tunnel face after an ore excursion returns.
local Backfill = {}

local function samePose(a, b)
    return a.x == b.x and a.y == b.y and a.z == b.z and a.facing == b.facing
end

function Backfill.seal(checkpoint, direction, ops)
    if type(checkpoint) ~= "table" or type(ops) ~= "table"
        or type(ops.pose) ~= "function" or type(ops.turnRight) ~= "function"
        or type(ops.turnLeft) ~= "function" or type(ops.selectCobblestone) ~= "function"
        or type(ops.place) ~= "function" or type(ops.inspect) ~= "function" then
        return { ok = false, code = "BACKFILL_INVALID_OPS" }
    end
    if not samePose(ops.pose(), checkpoint) then
        return { ok = false, code = "BACKFILL_CHECKPOINT_MISMATCH" }
    end
    if direction ~= "forward" and direction ~= "up" and direction ~= "down" then
        return { ok = false, code = "BACKFILL_INVALID_DIRECTION" }
    end

    local restoreTurn
    local function restore()
        if restoreTurn and ops[restoreTurn]() ~= true then return false end
        restoreTurn = nil
        return samePose(ops.pose(), checkpoint)
    end
    local function fail(code)
        if not restore() then return { ok = false, code = "BACKFILL_POSE_RESTORE_FAILED" } end
        return { ok = false, code = code }
    end

    if ops.selectCobblestone() ~= true then return fail("BACKFILL_COBBLESTONE_UNAVAILABLE") end
    if ops.place(direction) ~= true then
        return fail("BACKFILL_PLACE_FAILED")
    end
    local found, block = ops.inspect(direction)
    if found ~= true or type(block) ~= "table" or block.name ~= "minecraft:cobblestone" then
        return fail("BACKFILL_VERIFY_FAILED")
    end
    if not restore() then return { ok = false, code = "BACKFILL_POSE_RESTORE_FAILED" } end
    return { ok = true, code = "BACKFILL_SEALED" }
end

return Backfill
