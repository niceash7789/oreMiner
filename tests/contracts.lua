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
for _, status in ipairs({ "idle", "mining", "returning", "servicing", "resuming", "complete", "error" }) do
    expect(Contracts.isRunStatus(status), "known run status: " .. status)
end
expect(not Contracts.isRunStatus("paused"), "reject unknown run status")
expect(Contracts.isPhase("branch_outbound_lower"), "saved-state phase")
expect(Contracts.isPhase("active_baseline"), "active baseline phase")
expect(Contracts.isPhase("main_shaft") and Contracts.isPhase("junction"), "main route cursor phases")
expect(Contracts.isPhase("branch_turnaround") and Contracts.isPhase("branch_upper_return")
    and Contracts.isPhase("branch_lower_return")
    and Contracts.isPhase("branch_return_to_junction"), "branch cursor phases")
expect(not Contracts.isPhase("branch_outbound_upper"), "reject unspecified phase")
expect(Contracts.isWorkDomain("ore"), "known work domain")
expect(not Contracts.isWorkDomain("fleet"), "reject non-V1 work domain")
expect(Contracts.isPoseCertainty("known") and Contracts.isPoseCertainty("uncertain"),
    "pose certainty values")
expect(not Contracts.isPoseCertainty("estimated"), "reject unsupported pose certainty")
expect(Contracts.isFatalCode("POSITION_UNCERTAIN"), "known fatal code")
expect(not Contracts.isFatalCode("NO_BLOCK"), "ordinary result is not a fatal code")

print("shared contracts checks passed")
