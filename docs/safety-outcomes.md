# Safety outcomes

## Purpose and behavior

Separate an expected no-op from a safety failure in active mining. `DigClear.run` returns `NO_BLOCK` with `ok=true` when its target is empty; failed digs and exhausted limits remain typed failures. Ore scanning and branch progression carry those failure tables to the top-level mining decision instead of converting them to ordinary `false` or ignoring them.

## Public entry points

- `require("src.safety.result").new(ok, code, message, fields)` creates `{ok, code, message, retryable}`; `isSuccess(outcome)` checks success and `isResult(outcome)` validates the complete shape.
- `require("src.safety.dig_clear").run(options)` distinguishes `NO_BLOCK`, `UNBREAKABLE_BLOCK`, bounded-limit failures, and invalid policy.
- `require("src.mining.branch_progress").run(length, step)` preserves typed step failures and reports legacy `false` as a shortened branch.

## Invariants and assumptions

- A no-block result is successful and safe to continue past; it does not indicate a dig attempt.
- A detected block that cannot be dug is a fatal typed outcome. The caller must stop the mining operation.
- CC:Tweaked dig callbacks report literal `true` on success.
- Missing retryability is invalid; callers must explicitly opt into retry only for a known bounded transient condition.

## Dependencies and limitations

Pure Lua result and policy modules. `src/branch_miner.lua` consumes these outcomes for forward, overhead, and ore mining and checks branch scan results. `Result.new` defaults to `retryable=false`; the shared validator rejects outcomes that omit retryability. Movement and turn primitives return the existing first-value success boolean for coordinator compatibility and a structured result as their second value. This does not add persistence or guarantee recovery after a fatal error.

## Verification

Run `lua tests/safety_result.lua`, `lua tests/contracts.lua`, `lua tests/dig_clear.lua`, `lua tests/branch_progress.lua`, and the safety/return/inventory integration checks listed in `docs/STATUS.md`.
