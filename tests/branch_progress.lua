local BranchProgress = require("src.mining.branch_progress")
local FakeTurtle = require("tests.fake_turtle")

local turtle = FakeTurtle.new({ x = 0, y = 0, z = 0, facing = 0 })
local attempts = 0
local result = BranchProgress.run(4, function()
    for _ = 1, 10 do
        attempts = attempts + 1
        if turtle:move("forward", false) == true then
            return true
        end
    end
    return false
end)

assert(not result.ok and result.code == "BRANCH_SHORTENED")
assert(result.completed == 0 and result.requested == 4)
assert(attempts == 10, "blocked movement recovery should remain bounded")
assert(turtle.pose.z == 0, "failed fake-turtle moves must not update its pose")

local completed = 0
result = BranchProgress.run(3, function()
    completed = completed + 1
    return true
end)
assert(result.ok and result.code == "BRANCH_LENGTH_REACHED")
assert(result.completed == 3 and result.requested == 3)

local safetyFailure = { ok = false, code = "UNBREAKABLE_BLOCK", message = "bedrock" }
result = BranchProgress.run(3, function() return safetyFailure end)
assert(result == safetyFailure and result.code == "UNBREAKABLE_BLOCK",
    "typed safety failure must propagate unchanged through branch progress")

print("branch_progress: ok")
