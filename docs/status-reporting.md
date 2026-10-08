# Status reporting

## Purpose

Keep routine mining progress readable on the small terminal of a single CC:Tweaked turtle.

## Implemented behavior

The active branch miner reports compact main-tunnel, left/right branch, and completed-pair progress lines capped at 32 characters. `src.reporting.safe` protects terminal writes with `pcall`, and `src.reporting.statistics` keeps observational counters behind a small add/read interface whose failures fall back safely. Its summary API derives operational rates and formats a final job summary. Mining and safety outcomes do not depend on either optional reporting path.

## Public entry points

- `require("src.reporting.status")`
- `require("src.reporting.safe")`; `Reporting.log(sink, ...)` returns false if the sink is absent or raises.
- `require("src.reporting.statistics")`; `Statistics.new(initial)` returns `add(key, amount)`, `get(key)`, and `snapshot()` methods.
- `Statistics.jobSummary(stats, options)` builds aggregate metrics and accepts `startedAt`/`endedAt` elapsed-time values in seconds.
- `Statistics.formatJobSummary(summary)` returns four terminal-ready summary lines.
- `Status.phase(name, current, total, detail)` formats a compact phase line.
- `Status.branchComplete(current, total, blocks, fuel)` formats a compact pair-completion line.

## Invariants and assumptions

- The reporter only formats values; it does not read turtle state, move the turtle, or mutate counters.
- Routine phase lines are limited to 32 characters, matching the standard turtle terminal width.
- Counter updates remain at confirmed-action sites and are observational; they are not persisted. The active coordinator records confirmed dug blocks, tunnel advances, ore blocks by block ID, veins, fuel-consuming moves, completed branch pairs, successful inventory service trips, and successful paving placements. Arbitrary string counter keys support per-item or per-block type totals.
- Derived rates return zero when a denominator is missing or zero; invalid/missing elapsed-time inputs produce zero runtime.
- Reporting modules never read turtle state, move the turtle, or alter mining policy.

## Dependencies and limitations

Pure Lua; no CC APIs or other modules are required. Runtime uses the coordinator's terminal `print` sink. Statistics are not persisted. The active legacy coordinator has no staircase, floor, or torch-placement phases, so those counters remain available in the summary data model but are not printed as zero-valued claims. Ore-per-tunnel uses successful tunnel advances as its denominator; ore-per-fuel and ore-per-active-hour are operational ratios, not yield guarantees.

## Verification

`tests/status_reporting.lua` covers phase/final-summary formatting, derived rates, empty denominators, sink failure isolation, and counter access. `tests/vein_traversal.lua` covers the protected per-block accounting callback after successful vein entry. `tests/inventory_service.lua` verifies successful service reports its completion outcome. `tests/active_baseline_wiring.lua` injects a terminal exception during a full fake-turtle run and verifies both run completion and final-summary output.
