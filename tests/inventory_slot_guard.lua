-- Run from the project root with a Lua interpreter or CC:Tweaked computer.
local SlotGuard = require("src.inventory.slot_guard")

local fake = { selected = 7 }
function fake.getSelectedSlot()
    return fake.selected
end
function fake.select(slot)
    fake.selected = slot
    return true
end

local result = SlotGuard.run(fake, function()
    fake.select(2)
    return "done"
end)
assert(result.ok and result.value == "done", "operation result should be returned")
assert(fake.selected == 7, "original selection should be restored")

result = SlotGuard.run(fake, function()
    fake.select(3)
    return false
end)
assert(result.ok and result.value == false, "false operation value is not an exception")
assert(fake.selected == 7, "selection should restore when operation returns false")

result = SlotGuard.run(fake, function()
    fake.select(4)
    error("simulated helper failure")
end)
assert(not result.ok and result.code == "OPERATION_FAILED", "helper errors should be typed")
assert(fake.selected == 7, "selection should restore after helper error")

local broken = { selected = 5 }
function broken.getSelectedSlot()
    return broken.selected
end
function broken.select(slot)
    if slot == 5 then return false end
    broken.selected = slot
    return true
end
result = SlotGuard.run(broken, function()
    broken.select(1)
end)
assert(not result.ok and result.code == "SLOT_RESTORE_FAILED", "restore failure should be explicit")

print("inventory slot guard checks passed")
