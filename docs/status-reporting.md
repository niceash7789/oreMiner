# Status reporting

## Purpose

Keep routine mining progress readable on the small terminal of a single CC:Tweaked turtle.

## Implemented behavior

The active branch miner reports compact main-tunnel, left/right branch, and completed-pair progress lines capped at 32 characters. `src.reporting.safe` protects terminal writes with `pcall`, and `src.reporting.statistics` keeps observational counters behind a small add/read interface whose failures fall back safely. Its summary API derives operational rates and formats a final job summary. The `status` command loads and displays saved run state, committed pose, pose certainty, cursor, live fuel, occupied inventory slots versus threshold, last error, and the exact recovery classifier result without movement. The command converts the loaded checkpoint session to a defensive snapshot before formatting. Pending actions include a do-not-move recovery line. The root launcher forwards command arguments so `miner status` and `miner resume` reach the coordinator. `resume` is still limited to classifier-approved persisted cursors. Mining and safety outcomes do not depend on reporting.

## Public entry points

- `require("src.reporting.status")`
- `require("src.reporting.recovery_status")`; `RecoveryStatus.lines(state, loadCode, fuel, occupiedSlots, threshold)` formats a read-only recovery summary, and `display(..., sink)` writes it through a protected sink.
- `require("src.reporting.safe")`; `Reporting.log(sink, ...)` returns false if the sink is absent or raises.
- `require("src.reporting.statistics")`; `Statistics.new(initial)` returns `add(key, amount)`, `get(key)`, and `snapshot()` methods.
- `Statistics.jobSummary(stats, options)` builds aggregate metrics and accepts `startedAt`/`endedAt` elapsed-time values in seconds.
- `Statistics.formatJobSummary(summary)` returns four terminal-ready summary lines.
- `Status.phase(name, current, total, detail)` formats a compact phase line.
- `Status.branchComplete(current, total, blocks, fuel)` formats a compact pair-completion line.

## Invariants and assumptions

- Recovery presentation only formats supplied values. The command samples fuel and inventory counts but never moves, turns, digs, or mutates state.
- Routine phase lines are limited to 32 characters, matching the standard turtle terminal width.
- Counter updates remain at confirmed-action sites and are observational. The active coordinator records confirmed dug blocks, tunnel advances, ore blocks, veins, fuel-consuming moves, completed branch pairs, successful inventory service trips, and successful paving placements; the main checkpoint snapshot persists these values. Arbitrary string counter keys support per-item or per-block type totals.
- Derived rates return zero when a denominator is missing or zero; invalid/missing elapsed-time inputs produce zero runtime.
- Reporting modules never read turtle state, move the turtle, or alter mining policy.

## Dependencies and limitations

Status formatting is pure Lua and uses a supplied terminal sink. The command dispatcher and snapshot loader require CC:Tweaked's filesystem and textutils APIs; fuel and occupied-slot values come from turtle APIs. Resume remains unavailable because not every persisted phase can be restarted deterministically. Statistics persist in the main snapshot and active runtime accumulates only while the current process is running. Ore-per-tunnel uses successful tunnel advances as its denominator; ore-per-fuel and ore-per-active-hour are operational ratios, not yield guarantees.

## Verification

`tests/status_reporting.lua` covers phase/final-summary formatting, derived rates, empty denominators, sink failure isolation, and counter access. `tests/recovery_status.lua` covers loaded/missing/uncertain presentation and status/resume command dispatch while movement APIs are configured to fail if called. `tests/vein_traversal.lua` covers the protected per-block accounting callback after successful vein entry. `tests/inventory_service.lua` verifies successful service reports its completion outcome. `tests/active_baseline_wiring.lua` injects a terminal exception during a full fake-turtle run and verifies both run completion and final-summary output.
