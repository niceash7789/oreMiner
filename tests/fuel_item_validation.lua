local Validation = require("src.fuel.item_validation")

local calls = {}
local detail = { name = "example:solid_fuel" }
local api = {
    getItemDetail = function(slot) calls.detail = slot; return detail end,
    select = function(slot) calls.select = slot; return true end,
    refuel = function(amount) calls.refuel = amount; return true end,
}
local config = { fuel = { allowedItems = { "example:solid_fuel" } } }

local valid, code = Validation.verify(api, 4, config)
assert(valid and code == "FUEL_ITEM_VERIFIED")
assert(calls.detail == 4 and calls.select == 4 and calls.refuel == 0,
    "verification must select the configured stack and call refuel(0)")

api.refuel = function(amount) calls.refuel = amount; return 1 end
valid, code = Validation.verify(api, 4, config)
assert(not valid and code == "FUEL_ITEM_UNUSABLE",
    "only the literal true API result verifies fuel")
api.refuel = function() error("unconfigured items must not be checked") end
detail = { name = "minecraft:diamond" }
valid, code = Validation.verify(api, 4, config)
assert(not valid and code == "FUEL_ITEM_NOT_ALLOWED")
valid, code = Validation.verify(api, 0, config)
assert(not valid and code == "INVALID_FUEL_VALIDATION_INPUT")

print("fuel item validation checks passed")
