local Commitment = require("src.fuel.resume_commitment")

local target, code = Commitment.targetFuel(12, 100)
assert(target == 125 and code == nil,
    "resume fuel must cover both route legs, reserve, and one work move")

target = Commitment.targetFuel(0, 100, 3)
assert(target == 103, "a caller may specify a larger bounded work step")

target = Commitment.targetFuelForTrips(40, 41, 100, 1)
assert(target == 182,
    "resume fuel must include distinct home and replay routes, reserve, and work step")
target = Commitment.targetFuelForTrips(0, 0, 100, 1)
assert(target == 101, "zero-length trips still retain reserve and work fuel")

local invalid, invalidCode = Commitment.targetFuel(-1, 100)
assert(invalid == nil and invalidCode == "INVALID_RESUME_COMMITMENT")
invalid, invalidCode = Commitment.targetFuel(12, 100, 0)
assert(invalid == nil and invalidCode == "INVALID_RESUME_COMMITMENT")
invalid, invalidCode = Commitment.targetFuelForTrips(10, -1, 100, 1)
assert(invalid == nil and invalidCode == "INVALID_RESUME_COMMITMENT")

print("resume commitment checks passed")
