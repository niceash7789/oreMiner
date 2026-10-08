local status = require("src.reporting.status")
local Reporting = require("src.reporting.safe")
local Statistics = require("src.reporting.statistics")

assert(status.phase("MAIN", 5, 20, "step 2/3") == "[MAIN] 5/20 step 2/3")
assert(status.phase("BRANCH", 17, 20, "L out") == "[BRANCH] 17/20 L out")
assert(status.branchComplete(5, 20, 123, 456) == "[DONE] pair 5/20 B:123 F:456")
assert(#status.phase("A_VERY_LONG_PHASE_NAME", 123456, 987654, "a very long detail") <= 32)
assert(#status.branchComplete(123456, 987654, 123456789, "unlimited") <= 32)
assert(not Reporting.log(function() error("sink failed") end, "status"))
assert(Reporting.log(function(value) assert(value == "status") end, "status"))

local stats = Statistics.new({ blocks = 0 })
assert(stats:add("blocks", 2))
assert(stats:get("blocks") == 2)
assert(stats:add("blocks", "invalid"))
assert(stats:get("blocks") == 2)

print("status reporting tests passed")
