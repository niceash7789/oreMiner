-- Decide whether the default command may create a new mining run.
local Startup = {}

function Startup.newRunDecision(existing, stateCode)
    if stateCode == "POSITION_UNCERTAIN" then
        return { start = false,
            message = "POSITION_UNCERTAIN: pending movement or turn; reconcile pose before any action" }
    end
    if stateCode == "STATE_CORRUPT" then
        return { start = false,
            message = "STATE_CORRUPT: active state and backup are invalid; refusing to overwrite" }
    end
    if stateCode == "CONFIG_MISMATCH" then
        return { start = false,
            message = "CONFIG_MISMATCH: saved run configuration differs from current configuration" }
    end
    if existing and existing:status() ~= "complete" then
        return {
            start = false,
            message = "ACTIVE_STATE_PRESENT: new run refused. Run `miner status` to inspect state, then `miner resume` if the saved pose is known; pending actions require manual reconciliation.",
        }
    end
    return { start = true }
end

return Startup
