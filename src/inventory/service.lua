-- Inventory pressure, verified unloading, and return-trip coordination.
local Pressure = require("src.inventory.pressure")
local SlotGuard = require("src.inventory.slot_guard")
local Chest = require("src.inventory.chest")

local Service = {}

function Service.new(deps)
    local function pressureReached()
        local reached, result = Pressure.reached(
            deps.turtle,
            deps.config.inventory.pressureThreshold
        )
        if result == nil or type(result) == "number" then return reached end
        deps.reportError(result.message)
        return true
    end

    local function unloadToChest()
        local guarded = SlotGuard.run(deps.turtle, function()
            local result = Chest.unload(deps.turtle, deps.itemConfig)
            if not result.ok then
                deps.reportError("Could not unload into chest (" .. result.code .. ").")
                return false
            end
            return true
        end)
        return guarded.ok and guarded.value == true
    end

    local function face(facing)
        if deps.turnToFacing(facing) == false then
            deps.reportError("Could not turn to the required facing.")
            return false
        end
        return true
    end

    local function returnToStartAndUnload()
        local pos = deps.pose()
        local saved = { x = pos.x, y = pos.y, z = pos.z, facing = pos.facing }
        deps.report("[Inventory] Full - returning to chest...")

        while pos.y > 0 do
            if not deps.down() then deps.reportError("Could not move down for unload trip."); return false end
            pos = deps.pose()
        end
        while pos.y < 0 do
            if not deps.up() then deps.reportError("Could not move up for unload trip."); return false end
            pos = deps.pose()
        end

        if pos.x > 0 then
            if not face(3) then return false end
            while deps.pose().x > 0 do
                if not deps.safeForward() then deps.reportError("Could not return to main tunnel."); return false end
            end
        elseif pos.x < 0 then
            if not face(1) then return false end
            while deps.pose().x < 0 do
                if not deps.safeForward() then deps.reportError("Could not return to main tunnel."); return false end
            end
        end

        pos = deps.pose()
        if pos.z < 0 then
            if not face(2) then return false end
            while deps.pose().z < 0 do
                if not deps.safeForward() then deps.reportError("Could not return to start."); return false end
            end
        elseif pos.z > 0 then
            if not face(0) then return false end
            while deps.pose().z > 0 do
                if not deps.safeForward() then deps.reportError("Could not return to start."); return false end
            end
        end

        if not face(2) then return false end
        local hasBlock, block = deps.turtle.inspect()
        if not hasBlock or not block or not Chest.acceptsBlock(block.name, deps.config.base) then
            deps.reportError("No accepted chest found directly behind the starting position.")
            return false
        end
        if not unloadToChest() then return false end
        deps.report("[Inventory] Unloaded; configured retained quantities preserved.")

        if saved.z < 0 then
            if not face(0) then return false end
            while deps.pose().z > saved.z do
                if not deps.safeForward() then deps.reportError("Could not return to mining position."); return false end
            end
        elseif saved.z > 0 then
            if not face(2) then return false end
            while deps.pose().z < saved.z do
                if not deps.safeForward() then deps.reportError("Could not return to mining position."); return false end
            end
        end
        if saved.x > 0 then
            if not face(1) then return false end
            while deps.pose().x < saved.x do
                if not deps.safeForward() then deps.reportError("Could not return to branch position."); return false end
            end
        elseif saved.x < 0 then
            if not face(3) then return false end
            while deps.pose().x > saved.x do
                if not deps.safeForward() then deps.reportError("Could not return to branch position."); return false end
            end
        end
        pos = deps.pose()
        while pos.y < saved.y do
            if not deps.up() then deps.reportError("Could not restore mining height."); return false end
            pos = deps.pose()
        end
        while pos.y > saved.y do
            if not deps.down() then deps.reportError("Could not restore mining height."); return false end
            pos = deps.pose()
        end
        if not face(saved.facing) then return false end
        deps.report("[Inventory] Back at mining position.")
        return true
    end

    return {
        pressureReached = pressureReached,
        serviceIfNeeded = function()
            if not pressureReached() then return true end
            local serviced = returnToStartAndUnload()
            if serviced then return true, "SERVICE_COMPLETE" end
            return false, "INVENTORY_SERVICE_FAILED"
        end,
    }
end

return Service
