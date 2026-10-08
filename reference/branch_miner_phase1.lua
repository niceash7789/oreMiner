-- Branch Mining Program for ComputerCraft: Tweaked
-- Phase 1: Core Movement & Mining (MVP)

-- ============================================================================
-- GLOBAL STATE
-- ============================================================================

local pos = {x = 0, y = 0, z = 0, facing = 0}
-- facing: 0=north(-z), 1=east(+x), 2=south(+z), 3=west(-x)

local config = {
    branch_length = 30,
    num_branches = 20,
    spacing = 3,
    fuel_reserve = 100,
    auto_refuel_coal = true,
    pave = true,
    vein_mine = true
}

local stats = {
    blocks_mined = 0,
    branches_completed = 0,
    fuel_used = 0,
    ores_mined = 0,
    veins_found = 0
}

local FUEL_ITEMS = {
    ["minecraft:coal"] = true,
    ["minecraft:charcoal"] = true,
    ["minecraft:coal_block"] = true,
}

local PAVE_ITEMS = {
    ["minecraft:cobblestone"] = true,
    ["minecraft:cobbled_deepslate"] = true,
    ["minecraft:dirt"] = true,
    ["minecraft:netherrack"] = true,
}

-- ============================================================================
-- FUEL MANAGEMENT
-- ============================================================================

local function fuelToReturn()
    local dist = math.abs(pos.x) + math.abs(pos.y) + math.abs(pos.z)
    local buffer = math.max(10, math.ceil(dist * 0.2))
    return dist + buffer
end

local function getFuelNeeded()
    local moves_per_position =
        config.spacing + (config.branch_length * 4)

    if config.vein_mine then
        moves_per_position = moves_per_position + 4
    end

    local total_moves =
        config.num_branches * moves_per_position

    local final_distance =
        config.num_branches * config.spacing

    local return_trip =
        final_distance + 50

    return total_moves + return_trip
end

local function refuel(needed)
    local level = turtle.getFuelLevel()

    if level == "unlimited" then
        return true
    end

    if level >= needed then
        return true
    end

    local originalSlot = turtle.getSelectedSlot()

    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then
            turtle.select(slot)

            if turtle.refuel(0) then
                while turtle.getFuelLevel() < needed
                    and turtle.getItemCount(slot) > 0 do
                    turtle.refuel(1)
                end

                if turtle.getFuelLevel() >= needed then
                    turtle.select(originalSlot)
                    return true
                end
            end
        end
    end

    turtle.select(originalSlot)

    return turtle.getFuelLevel() >= needed
end

local function tryAutoRefuelCoal()
    if not config.auto_refuel_coal then
        return
    end

    local level = turtle.getFuelLevel()

    if level == "unlimited" then
        return
    end

    if level >= config.fuel_reserve then
        return
    end

    local originalSlot =
        turtle.getSelectedSlot()

    local refueled = false

    for slot = 1, 16 do
        local detail =
            turtle.getItemDetail(slot)

        if detail and FUEL_ITEMS[detail.name] then
            turtle.select(slot)

            while turtle.getFuelLevel() < config.fuel_reserve
                and turtle.getItemCount(slot) > 0 do
                turtle.refuel(1)
            end

            refueled = true

            if turtle.getFuelLevel() >= config.fuel_reserve then
                break
            end
        end
    end

    if refueled then
        print(
            string.format(
                "  [Fuel] Auto-refueled to %d",
                turtle.getFuelLevel()
            )
        )
    end

    turtle.select(originalSlot)
end

local function checkFuel()
    local level = turtle.getFuelLevel()

    if level == "unlimited" then
        return true
    end

    if level < 1 then
        if not refuel(config.fuel_reserve) then
            print("WARNING: Out of fuel!")
            print("Current fuel: " .. level)
            print("Please add fuel items to inventory")
            return false
        end
    end

    local returnCost = fuelToReturn()

    if level <= returnCost then
        print(
            string.format(
                "  [Fuel] WARNING: Fuel (%d) <= return cost (%d)!",
                level,
                returnCost
            )
        )

        local target =
            returnCost + config.fuel_reserve

        if not refuel(target) then
            print(
                string.format(
                    "  [Fuel] CRITICAL: Cannot refuel to %d! Current: %d",
                    target,
                    turtle.getFuelLevel()
                )
            )
        end
    end

    return true
end

-- ============================================================================
-- POSITION TRACKING
-- ============================================================================

local function updatePosition(dx, dy, dz)
    pos.x = pos.x + dx
    pos.y = pos.y + dy
    pos.z = pos.z + dz
end

local function updateFacing(delta)
    pos.facing =
        (pos.facing + delta) % 4
end

-- ============================================================================
-- CORE MOVEMENT FUNCTIONS
-- ============================================================================

local function forward()
    if not checkFuel() then
        return false, "Out of fuel"
    end

    if turtle.forward() then
        if pos.facing == 0 then
            updatePosition(0, 0, -1)
        elseif pos.facing == 1 then
            updatePosition(1, 0, 0)
        elseif pos.facing == 2 then
            updatePosition(0, 0, 1)
        elseif pos.facing == 3 then
            updatePosition(-1, 0, 0)
        end

        stats.fuel_used =
            stats.fuel_used + 1

        return true
    end

    return false, "Movement blocked"
end

local function back()
    if not checkFuel() then
        return false, "Out of fuel"
    end

    if turtle.back() then
        if pos.facing == 0 then
            updatePosition(0, 0, 1)
        elseif pos.facing == 1 then
            updatePosition(-1, 0, 0)
        elseif pos.facing == 2 then
            updatePosition(0, 0, -1)
        elseif pos.facing == 3 then
            updatePosition(1, 0, 0)
        end

        stats.fuel_used =
            stats.fuel_used + 1

        return true
    end

    return false, "Movement blocked"
end

local function up()
    if not checkFuel() then
        return false, "Out of fuel"
    end

    if turtle.up() then
        updatePosition(0, 1, 0)

        stats.fuel_used =
            stats.fuel_used + 1

        return true
    end

    return false, "Movement blocked"
end

local function down()
    if not checkFuel() then
        return false, "Out of fuel"
    end

    if turtle.down() then
        updatePosition(0, -1, 0)

        stats.fuel_used =
            stats.fuel_used + 1

        return true
    end

    return false, "Movement blocked"
end

local function turnLeft()
    turtle.turnLeft()
    updateFacing(-1)
end

local function turnRight()
    turtle.turnRight()
    updateFacing(1)
end

-- ============================================================================
-- SAFE DIGGING
-- ============================================================================

local function digForward()
    local dug = false

    while turtle.detect() do
        if turtle.dig() then
            dug = true

            stats.blocks_mined =
                stats.blocks_mined + 1
        else
            return false
        end

        sleep(0.5)
    end

    return dug
end

local function digUp()
    local dug = false

    while turtle.detectUp() do
        if turtle.digUp() then
            dug = true

            stats.blocks_mined =
                stats.blocks_mined + 1
        else
            return false
        end

        sleep(0.5)
    end

    return dug
end

local function digDown()
    local dug = false

    while turtle.detectDown() do
        if turtle.digDown() then
            dug = true

            stats.blocks_mined =
                stats.blocks_mined + 1
        else
            return false
        end

        sleep(0.5)
    end

    return dug
end

local function paveDown()
    if not config.pave then
        return false
    end

    if turtle.detectDown() then
        return false
    end

    local originalSlot =
        turtle.getSelectedSlot()

    for slot = 1, 16 do
        local detail =
            turtle.getItemDetail(slot)

        if detail and PAVE_ITEMS[detail.name] then
            turtle.select(slot)

            if turtle.placeDown() then
                turtle.select(originalSlot)
                return true
            end
        end
    end

    turtle.select(originalSlot)

    return false
end

-- ============================================================================
-- ORE VEIN MINING
-- ============================================================================

local function isOre(name)
    return name:find("_ore$") ~= nil
end

local function getPositionKey(x, y, z)
    return x .. "," .. y .. "," .. z
end

local function getForwardPosition()
    if pos.facing == 0 then
        return pos.x, pos.y, pos.z - 1
    elseif pos.facing == 1 then
        return pos.x + 1, pos.y, pos.z
    elseif pos.facing == 2 then
        return pos.x, pos.y, pos.z + 1
    else
        return pos.x - 1, pos.y, pos.z
    end
end

local function safeForward()
    if not forward() then
        digForward()
        return forward()
    end

    return true
end

local function safeBack()
    if back() then
        return true
    end

    turnRight()
    turnRight()

    safeForward()

    turnRight()
    turnRight()

    return true
end

-- ============================================================================
-- INVENTORY / CHEST UNLOADING
-- ============================================================================

local function turnToFacing(targetFacing)
    local delta =
        (targetFacing - pos.facing) % 4

    if delta == 1 then
        turnRight()
    elseif delta == 2 then
        turnRight()
        turnRight()
    elseif delta == 3 then
        turnLeft()
    end
end

local function inventoryFull()
    for slot = 1, 16 do
        if turtle.getItemCount(slot) == 0 then
            return false
        end
    end

    return true
end

local function consolidateKeepItem(itemName)
    local keepSlot = nil

    for slot = 1, 16 do
        local detail =
            turtle.getItemDetail(slot)

        if detail and detail.name == itemName then
            if not keepSlot then
                keepSlot = slot
            else
                turtle.select(slot)
                turtle.transferTo(keepSlot)
            end
        end
    end

    return keepSlot
end

local function unloadToChest()
    local originalSlot =
        turtle.getSelectedSlot()

    local keepCobbleSlot =
        consolidateKeepItem(
            "minecraft:cobblestone"
        )

    local keepCoalSlot =
        consolidateKeepItem(
            "minecraft:coal"
        )

    for slot = 1, 16 do
        if slot ~= keepCobbleSlot
            and slot ~= keepCoalSlot
            and turtle.getItemCount(slot) > 0 then

            turtle.select(slot)

            if not turtle.drop() then
                turtle.select(originalSlot)

                print(
                    "ERROR: Could not unload into chest."
                )

                print(
                    "The chest may be full."
                )

                return false
            end

            if turtle.getItemCount(slot) > 0 then
                turtle.select(originalSlot)

                print(
                    "ERROR: Chest filled before inventory was emptied."
                )

                return false
            end
        end
    end

    turtle.select(originalSlot)

    return true
end

local function returnToStartAndUnload()
    local saved = {
        x = pos.x,
        y = pos.y,
        z = pos.z,
        facing = pos.facing
    }

    print(
        "  [Inventory] Full - returning to chest..."
    )

    while pos.y > 0 do
        if not down() then
            print(
                "ERROR: Could not move down for unload trip."
            )

            return false
        end
    end

    while pos.y < 0 do
        if not up() then
            print(
                "ERROR: Could not move up for unload trip."
            )

            return false
        end
    end

    -- Return from branch to main tunnel.
    if pos.x > 0 then
        turnToFacing(3)

        while pos.x > 0 do
            if not safeForward() then
                print(
                    "ERROR: Could not return to main tunnel."
                )

                return false
            end
        end

    elseif pos.x < 0 then

        turnToFacing(1)

        while pos.x < 0 do
            if not safeForward() then
                print(
                    "ERROR: Could not return to main tunnel."
                )

                return false
            end
        end
    end

    -- Main tunnel back to starting point.
    if pos.z < 0 then
        turnToFacing(2)

        while pos.z < 0 do
            if not safeForward() then
                print(
                    "ERROR: Could not return to start."
                )

                return false
            end
        end

    elseif pos.z > 0 then

        turnToFacing(0)

        while pos.z > 0 do
            if not safeForward() then
                print(
                    "ERROR: Could not return to start."
                )

                return false
            end
        end
    end

    -- Chest is behind the turtle's original
    -- starting position.
    turnToFacing(2)

    local hasBlock, block =
        turtle.inspect()

    if not hasBlock
        or not block.name:find("chest") then

        print(
            "ERROR: No chest found directly behind the starting position."
        )

        print(
            "Place a chest behind where the turtle started."
        )

        return false
    end

    if not unloadToChest() then
        return false
    end

    print(
        "  [Inventory] Unloaded."
    )

    print(
        "  [Inventory] Keeping one stack of cobblestone and one stack of coal."
    )

    -- Return down main tunnel.
    if saved.z < 0 then
        turnToFacing(0)

        while pos.z > saved.z do
            if not safeForward() then
                print(
                    "ERROR: Could not return to mining position."
                )

                return false
            end
        end

    elseif saved.z > 0 then

        turnToFacing(2)

        while pos.z < saved.z do
            if not safeForward() then
                print(
                    "ERROR: Could not return to mining position."
                )

                return false
            end
        end
    end

    -- Return along side branch.
    if saved.x > 0 then
        turnToFacing(1)

        while pos.x < saved.x do
            if not safeForward() then
                print(
                    "ERROR: Could not return to branch position."
                )

                return false
            end
        end

    elseif saved.x < 0 then

        turnToFacing(3)

        while pos.x > saved.x do
            if not safeForward() then
                print(
                    "ERROR: Could not return to branch position."
                )

                return false
            end
        end
    end

    while pos.y < saved.y do
        if not up() then
            print(
                "ERROR: Could not restore mining height."
            )

            return false
        end
    end

    while pos.y > saved.y do
        if not down() then
            print(
                "ERROR: Could not restore mining height."
            )

            return false
        end
    end

    turnToFacing(saved.facing)

    print(
        "  [Inventory] Back at mining position."
    )

    return true
end

local function serviceInventoryIfFull()
    if not inventoryFull() then
        return true
    end

    return returnToStartAndUnload()
end

-- ============================================================================
-- VEIN MINING
-- ============================================================================

local function mineVein(oreName, visited)
    visited[
        getPositionKey(
            pos.x,
            pos.y,
            pos.z
        )
    ] = true

    for i = 1, 4 do
        local hasBlock, data =
            turtle.inspect()

        if hasBlock
            and data.name == oreName then

            local fx, fy, fz =
                getForwardPosition()

            if not visited[
                getPositionKey(
                    fx,
                    fy,
                    fz
                )
            ] then

                digForward()

                stats.ores_mined =
                    stats.ores_mined + 1

                if forward() then
                    mineVein(
                        oreName,
                        visited
                    )

                    safeBack()
                end
            end
        end

        turnRight()
    end

    local hasUp, dataUp =
        turtle.inspectUp()

    if hasUp
        and dataUp.name == oreName then

        if not visited[
            getPositionKey(
                pos.x,
                pos.y + 1,
                pos.z
            )
        ] then

            digUp()

            stats.ores_mined =
                stats.ores_mined + 1

            if up() then
                mineVein(
                    oreName,
                    visited
                )

                down()
            end
        end
    end

    local hasDown, dataDown =
        turtle.inspectDown()

    if hasDown
        and dataDown.name == oreName then

        if not visited[
            getPositionKey(
                pos.x,
                pos.y - 1,
                pos.z
            )
        ] then

            digDown()

            stats.ores_mined =
                stats.ores_mined + 1

            if down() then
                mineVein(
                    oreName,
                    visited
                )

                up()
            end
        end
    end
end

local function checkAndMineOre()
    local hasBlock, data =
        turtle.inspect()

    if hasBlock
        and isOre(data.name) then

        stats.veins_found =
            stats.veins_found + 1

        stats.ores_mined =
            stats.ores_mined + 1

        digForward()

        if forward() then
            local visited = {}

            mineVein(
                data.name,
                visited
            )

            safeBack()
        end
    end
end

local function checkAndMineOreUp()
    local hasBlock, data =
        turtle.inspectUp()

    if hasBlock
        and isOre(data.name) then

        stats.veins_found =
            stats.veins_found + 1

        stats.ores_mined =
            stats.ores_mined + 1

        digUp()

        if up() then
            local visited = {}

            mineVein(
                data.name,
                visited
            )

            down()
        end
    end
end

local function checkAndMineOreDown()
    local hasBlock, data =
        turtle.inspectDown()

    if hasBlock
        and isOre(data.name) then

        stats.veins_found =
            stats.veins_found + 1

        stats.ores_mined =
            stats.ores_mined + 1

        digDown()

        if down() then
            local visited = {}

            mineVein(
                data.name,
                visited
            )

            up()
        end
    end
end

-- ============================================================================
-- MINING FUNCTIONS
-- ============================================================================

local function mineForward()
    digForward()
    digUp()

    local attempts = 0

    while not forward() do
        attempts =
            attempts + 1

        if attempts > 10 then
            print(
                "ERROR: Cannot move forward after 10 attempts"
            )

            return false
        end

        if turtle.detect() then

            if not turtle.dig() then
                print(
                    "ERROR: Cannot dig block (bedrock?)"
                )

                return false
            end

        elseif turtle.attack() then

        else
            sleep(0.5)
        end
    end

    paveDown()

    return true
end

local function mineBranch(length)
    local actualLength = length

    for i = 1, length do

        if not serviceInventoryIfFull() then
            return false
        end

        if not mineForward() then
            print(
                "  Branch mining stopped at block "
                    .. i
            )

            actualLength =
                i - 1

            break
        end

        if config.vein_mine then

            turnLeft()
            checkAndMineOre()
            turnRight()

            turnRight()
            checkAndMineOre()
            turnLeft()

            checkAndMineOreDown()
        end

        if not serviceInventoryIfFull() then
            return false
        end
    end

    digUp()

    if config.vein_mine then

        up()

        turnRight()
        turnRight()

        for i = 1, actualLength do

            if not serviceInventoryIfFull() then
                return false
            end

            turnLeft()
            checkAndMineOre()
            turnRight()

            turnRight()
            checkAndMineOre()
            turnLeft()

            checkAndMineOreUp()

            if not serviceInventoryIfFull() then
                return false
            end

            safeForward()
        end

        down()

    else

        turnRight()
        turnRight()

        for i = 1, actualLength do

            if not forward() then

                digForward()

                if not forward() then
                    print(
                        "ERROR: Cannot return from branch!"
                    )

                    return false
                end
            end
        end
    end

    return true
end

-- ============================================================================
-- FUEL STATUS
-- ============================================================================

local function printFuelStatus(branch_num)
    local level =
        turtle.getFuelLevel()

    if level == "unlimited" then
        return
    end

    local returnCost =
        fuelToReturn()

    local remaining_branches =
        config.num_branches
        - branch_num

    local moves_per_branch =
        config.spacing
        + (config.branch_length * 4)

    if config.vein_mine then
        moves_per_branch =
            moves_per_branch + 4
    end

    local fuel_to_finish =
        remaining_branches
        * moves_per_branch

    local efficiency = "N/A"

    if stats.fuel_used > 0 then
        efficiency =
            string.format(
                "%.1f",
                stats.blocks_mined
                    / stats.fuel_used
            )
    end

    print(
        string.format(
            "  [Fuel] Level: %d | Return cost: %d | To finish: ~%d | Blocks/fuel: %s",
            level,
            returnCost,
            fuel_to_finish,
            efficiency
        )
    )
end

-- ============================================================================
-- MAIN MINING PATTERN
-- ============================================================================

local function executeMining()

    local fuelLevel =
        turtle.getFuelLevel()

    local fuelNeeded =
        getFuelNeeded()

    print("=== Fuel Check ===")

    if fuelLevel == "unlimited" then

        print(
            "Fuel: unlimited (creative mode)"
        )

    else

        print(
            string.format(
                "Current fuel: %d",
                fuelLevel
            )
        )

        print(
            string.format(
                "Estimated needed: %d",
                fuelNeeded
            )
        )

        if fuelLevel < fuelNeeded then

            print("")
            print(
                "WARNING: Low fuel! Attempting to refuel..."
            )

            if not refuel(fuelNeeded) then

                print(
                    "Could not get enough fuel."
                )

                print(
                    "Continuing anyway, will try to refuel during operation."
                )

            else

                print(
                    string.format(
                        "Refueled! New level: %d",
                        turtle.getFuelLevel()
                    )
                )
            end
        end
    end

    print("")

    print(
        "Starting branch mining operation..."
    )

    print(
        string.format(
            "Position: x=%d, y=%d, z=%d, facing=%d",
            pos.x,
            pos.y,
            pos.z,
            pos.facing
        )
    )

    print("")

    for branch = 1, config.num_branches do

        print(
            string.format(
                "[Branch %d/%d] Mining main tunnel (%d blocks)...",
                branch,
                config.num_branches,
                config.spacing
            )
        )

        for step = 1, config.spacing do

            if not serviceInventoryIfFull() then
                return false
            end

            if not mineForward() then

                print(
                    "ERROR: Mining stopped in main tunnel"
                )

                return false
            end

            if not serviceInventoryIfFull() then
                return false
            end
        end

        print(
            string.format(
                "[Branch %d/%d] Mining LEFT branch (%d blocks)...",
                branch,
                config.num_branches,
                config.branch_length
            )
        )

        turnLeft()

        if not mineBranch(
            config.branch_length
        ) then

            print(
                "ERROR: Left branch mining failed"
            )

            return false
        end

        tryAutoRefuelCoal()

        if not serviceInventoryIfFull() then
            return false
        end

        print(
            string.format(
                "[Branch %d/%d] Mining RIGHT branch (%d blocks)...",
                branch,
                config.num_branches,
                config.branch_length
            )
        )

        if not mineBranch(
            config.branch_length
        ) then

            print(
                "ERROR: Right branch mining failed"
            )

            return false
        end

        tryAutoRefuelCoal()

        if not serviceInventoryIfFull() then
            return false
        end

        turnRight()

        stats.branches_completed =
            stats.branches_completed + 1

        local currentFuel =
            turtle.getFuelLevel()

        local fuelStr =
            currentFuel == "unlimited"
            and "unlimited"
            or tostring(currentFuel)

        print(
            string.format(
                "[Branch %d/%d] DONE (L+R) | Mined: %d | Fuel: %s | Pos: %d,%d,%d",
                branch,
                config.num_branches,
                stats.blocks_mined,
                fuelStr,
                pos.x,
                pos.y,
                pos.z
            )
        )

        printFuelStatus(branch)

        print("")
    end

    print("")
    print(
        "=== Mining Complete! ==="
    )

    print(
        string.format(
            "Total branches: %d",
            stats.branches_completed
        )
    )

    print(
        string.format(
            "Total blocks mined: %d",
            stats.blocks_mined
        )
    )

    print(
        string.format(
            "Fuel used: %d",
            stats.fuel_used
        )
    )

    local endFuel =
        turtle.getFuelLevel()

    if endFuel ~= "unlimited" then

        print(
            string.format(
                "Ending fuel: %d",
                endFuel
            )
        )

        if stats.fuel_used > 0 then

            print(
                string.format(
                    "Mining efficiency: %.1f blocks/fuel",
                    stats.blocks_mined
                        / stats.fuel_used
                )
            )
        end
    end

    if config.vein_mine then

        print(
            string.format(
                "Veins found: %d",
                stats.veins_found
            )
        )

        print(
            string.format(
                "Ore blocks mined: %d",
                stats.ores_mined
            )
        )
    end

    print(
        string.format(
            "Final position: x=%d, y=%d, z=%d",
            pos.x,
            pos.y,
            pos.z
        )
    )

    return true
end

-- ============================================================================
-- USER INTERFACE
-- ============================================================================

local function getUserInput(
    prompt,
    default
)

    write(
        prompt
            .. " (default: "
            .. tostring(default)
            .. "): "
    )

    local input = read()

    if input == ""
        or input == nil then

        return default
    end

    return tonumber(input)
        or default
end

local function getConfiguration()

    print(
        "=== Branch Mining Configuration ==="
    )

    print("")

    config.branch_length =
        getUserInput(
            "Branch length",
            30
        )

    config.num_branches =
        getUserInput(
            "Number of branches",
            20
        )

    config.spacing =
        getUserInput(
            "Spacing between branches",
            3
        )

    write(
        "Enable floor paving? (y/n, default: y): "
    )

    local paveInput = read()

    config.pave =
        paveInput ~= "n"
        and paveInput ~= "N"

    write(
        "Enable ore vein mining? (y/n, default: y): "
    )

    local veinInput = read()

    config.vein_mine =
        veinInput ~= "n"
        and veinInput ~= "N"

    print("")
    print("Configuration:")

    print(
        "  Branch length: "
            .. config.branch_length
    )

    print(
        "  Number of branches: "
            .. config.num_branches
    )

    print(
        "  Spacing: "
            .. config.spacing
    )

    print(
        "  Floor paving: "
            .. (
                config.pave
                and "yes"
                or "no"
            )
    )

    print(
        "  Ore vein mining: "
            .. (
                config.vein_mine
                and "yes"
                or "no"
            )
    )

    print(
        "  Chest unload: enabled"
    )

    print(
        "  Chest position: directly behind start"
    )

    print(
        "  Keeps: 1 stack cobblestone + 1 stack coal"
    )

    print("")

    write(
        "Start mining? (y/n): "
    )

    local confirm = read()

    return confirm == "y"
        or confirm == "Y"
        or confirm == ""
end

-- ============================================================================
-- MAIN
-- ============================================================================

local function main()

    print(
        "=== ComputerCraft Branch Mining Program ==="
    )

    print("")

    if getConfiguration() then
        executeMining()
    else
        print(
            "Mining cancelled."
        )
    end
end

main()

