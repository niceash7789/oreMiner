local Contracts = require("src.core.contracts")

local function expect(value, message)
    if not value then error(message or "contract assertion failed") end
end

expect(Contracts.isPose({ x = 0, y = -8, z = 13, facing = 0 }), "valid north pose")
expect(Contracts.isPose({ x = -2, y = 1, z = 3, facing = 3 }), "valid west pose")
expect(not Contracts.isPose({ x = 0, y = 0, z = 0, facing = 4 }), "reject facing outside 0..3")
expect(not Contracts.isPose({ x = 0.5, y = 0, z = 0, facing = 0 }), "reject fractional coordinate")
expect(not Contracts.isPose({ x = 0, y = 0, z = 0 }), "reject incomplete pose")

expect(Contracts.isResult({ ok = true, code = "NO_BLOCK" }), "valid success result")
expect(Contracts.isResult({ ok = false, code = "BLOCKED", retryable = false }), "valid failure result")
expect(not Contracts.isResult({ ok = 1, code = "BLOCKED" }), "reject non-boolean result status")
expect(not Contracts.isResult({ ok = false, code = "" }), "reject empty result code")
expect(not Contracts.isResult({ ok = false, code = "BLOCKED", retryable = "no" }), "reject invalid retryable")

expect(Contracts.WORK_DOMAINS.shaft and Contracts.WORK_DOMAINS.floor
    and Contracts.WORK_DOMAINS.ore and Contracts.WORK_DOMAINS.service, "work domains")
expect(Contracts.RUN_STATUSES.mining and Contracts.RUN_STATUSES.complete
    and Contracts.RUN_STATUSES.error, "run statuses")
expect(Contracts.isFatalCode("POSITION_UNCERTAIN"), "known fatal code")
expect(not Contracts.isFatalCode("NO_BLOCK"), "ordinary result is not a fatal code")

print("shared contracts checks passed")
