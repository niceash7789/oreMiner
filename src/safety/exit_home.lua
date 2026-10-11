-- Converts a normal keyboard termination into the existing checked home command.
local ExitHome = {}

function ExitHome.isTermination(value)
    local message = tostring(value)
    return message == "Terminated" or message:match(":%d+: Terminated$") ~= nil
end

-- Run the miner as a child coroutine so Ctrl+T is held by the supervisor.
-- In particular, a turtle API already waiting for its response may finish
-- and commit before the coordinator observes the stop request.
function ExitHome.runActive(run, pullEventRaw, requestStop)
    local worker = coroutine.create(run)
    local ok, filter = coroutine.resume(worker)
    while ok and coroutine.status(worker) ~= "dead" do
        local event = table.pack(pullEventRaw())
        if event[1] == "terminate" then
            requestStop()
        elseif filter == nil or filter == event[1] then
            ok, filter = coroutine.resume(worker, table.unpack(event, 1, event.n))
        end
    end
    return ok, filter
end

function ExitHome.run(runHome, report)
    report("Exit requested; returning home over the saved route.")
    local ok, problem = pcall(runHome)
    if not ok then
        report("Automatic home stopped safely: " .. tostring(problem))
        return false
    end
    return true
end

return ExitHome
