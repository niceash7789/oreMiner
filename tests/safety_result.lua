local Result = require("src.safety.result")
local Contracts = require("src.core.contracts")

local success = Result.new(true, "MOVED")
assert(Result.isResult(success) and Contracts.isResult(success))
assert(success.ok and success.retryable == false)

local retryable = Result.new(false, "ENTITY_BLOCKED", "Temporary obstruction.", {
    retryable = true,
})
assert(Result.isResult(retryable) and Contracts.isResult(retryable))
assert(not retryable.ok and retryable.retryable)

assert(not Result.isResult({ ok = false, code = "BLOCKED" }))
assert(not pcall(function() Result.new(false, "") end))

print("safety result checks passed")
