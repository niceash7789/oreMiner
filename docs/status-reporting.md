# Status reporting

## Purpose

Keep routine mining progress readable on the small terminal of a single CC:Tweaked turtle.

## Implemented behavior

The active branch miner reports compact main-tunnel, left/right branch, and completed-pair progress lines capped at 32 characters. `src.reporting.safe` protects terminal writes with `pcall`, and `src.reporting.statistics` keeps observational counters behind a small add/read interface whose failures fall back safely. Mining and safety outcomes do not depend on either optional reporting path.

## Public entry points

- `require("src.reporting.status")`
- `require("src.reporting.safe")`; `Reporting.log(sink, ...)` returns false if the sink is absent or raises.
- `require("src.reporting.statistics")`; `Statistics.new(initial)` returns `add(key, amount)` and `get(key)` methods.
- `Status.phase(name, current, total, detail)` formats a compact phase line.
- `Status.branchComplete(current, total, blocks, fuel)` formats a compact pair-completion line.

## Invariants and assumptions

- The reporter only formats values; it does not read turtle state, move the turtle, or mutate counters.
- Routine phase lines are limited to 32 characters, matching the standard turtle terminal width.
- Counter updates remain at confirmed-action sites and are observational; they are not persisted.
- Reporting modules never read turtle state, move the turtle, or alter mining policy.

## Dependencies and limitations

Pure Lua; no CC APIs or other modules are required. Runtime uses the coordinator's terminal `print` sink. Statistics are not persisted, and this slice does not implement the detailed MVP P2 measurements listed in `MINER_PLAN.md`.

## Verification

`tests/status_reporting.lua` covers formatting, sink failure isolation, and counter access. `tests/active_baseline_wiring.lua` injects a terminal exception during a full fake-turtle run and verifies the run completes. Lua parse checks cover both reporting modules, the coordinator, and focused tests.
