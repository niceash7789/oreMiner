-- Verify a configured fuel item without consuming it.
local ItemPolicy = require("src.config.item_policy")

local FuelItemValidation = {}

function FuelItemValidation.verify(api, slot, config)
    if type(api) ~= "table" or type(slot) ~= "number"
        or slot ~= math.floor(slot) or slot < 1 or slot > 16
        or type(api.getItemDetail) ~= "function"
        or type(api.select) ~= "function" or type(api.refuel) ~= "function" then
        return false, "INVALID_FUEL_VALIDATION_INPUT"
    end
    local detail = api.getItemDetail(slot)
    if type(detail) ~= "table" or not ItemPolicy.isFuel(detail.name, config) then
        return false, "FUEL_ITEM_NOT_ALLOWED"
    end
    if api.select(slot) ~= true then return false, "FUEL_SLOT_SELECT_FAILED" end
    if api.refuel(0) ~= true then return false, "FUEL_ITEM_UNUSABLE" end
    return true, "FUEL_ITEM_VERIFIED"
end

return FuelItemValidation
