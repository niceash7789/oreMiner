# Retry policy

## Purpose

Provide one bounded retry contract for the single turtle's movement, block, and entity recovery operations.

## Implemented behavior

`Retry.run` invokes a typed operation at most its configured attempt limit. It returns immediately on success or a non-retryable outcome. If every attempt is retryable and fails, it returns the caller's exhaustion code with `retryable = false` and the exact attempt count. Invalid limits and malformed outcomes fail closed with typed errors. Dig clearing also caps attempts at 64 and stops on its elapsed-time budget. Forward recovery accepts only boolean move and detection results, retries solid blocks through dig clearing, and makes no more than the configured entity attack/wait attempts.

## Public entry points

- `require("src.safety.retry")`
- `Retry.result(ok, code, message, retryable, attempts)` creates the shared result shape.
- `Retry.run(limit, exhaustedCode, operation)` applies the bounded policy.
- `require("src.config.defaults").safety` provides `moveRetries = 5`, `digRetries = 12`, `entityRetries = 5`, and `retryDelay = 0.4` defaults.

## Invariants and assumptions

- A retry limit is a positive integer no greater than 64; dig-clear enforces this bound even when called outside validated configuration.
- Each callback returns `{ok, code, message, retryable}` with boolean `ok` and `retryable` fields.
- The operation owns classification and only marks outcomes retryable when another attempt is safe.
- Exhaustion is terminal and typed; the runner never sleeps or calls turtle APIs.
- Forward recovery propagates non-`MOVE_FAILED` movement outcomes before inspecting or changing the world. Solid-block detection never enters the entity attack path.

## Dependencies and limitations

Pure Lua with no runtime dependencies. `src/safety/dig_clear.lua` applies configured attempt and time bounds to forward/up/down clearing. `src/safety/forward_recovery.lua` integrates checked forward movement with bounded solid-block clearing and entity attack/wait recovery, and the active coordinator supplies these callbacks from `src/branch_miner.lua`. Liquids and unknown non-solid obstructions are not classified here. Focused tests cover attempt/time bounds and typed failure paths; execution is pending a Lua runtime.

## Verification

Focused checks are `tests/retry_policy.lua`, `tests/dig_clear.lua`, `tests/forward_recovery.lua`, and `tests/active_baseline_wiring.lua`. They could not be run in this environment: no Lua, LuaJIT, or `luac` executable is available, WSL is not installed, and the Windows Python launcher could not start. Earlier results are historical and are not treated as verification for this change.
