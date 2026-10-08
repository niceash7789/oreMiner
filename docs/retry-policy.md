# Retry policy

## Purpose

Provide one bounded retry contract for the single turtle's movement, block, and entity recovery operations.

## Implemented behavior

`Retry.run` invokes a typed operation at most its configured attempt limit. It returns immediately on success or a non-retryable outcome. If every attempt is retryable and fails, it returns the caller's exhaustion code with `retryable = false` and the exact attempt count. Invalid limits and malformed outcomes fail closed with typed errors.

## Public entry points

- `require("src.safety.retry")`
- `Retry.result(ok, code, message, retryable, attempts)` creates the shared result shape.
- `Retry.run(limit, exhaustedCode, operation)` applies the bounded policy.
- `require("src.config.defaults").safety` provides `moveRetries = 5`, `digRetries = 12`, `entityRetries = 5`, and `retryDelay = 0.4` defaults.

## Invariants and assumptions

- A retry limit is a positive integer no greater than 64.
- Each callback returns `{ok, code, message, retryable}` with boolean `ok` and `retryable` fields.
- The operation owns classification and only marks outcomes retryable when another attempt is safe.
- Exhaustion is terminal and typed; the runner never sleeps or calls turtle APIs.

## Dependencies and limitations

Pure Lua with no runtime dependencies. The active miner does not yet route movement, digging, or entity handling through this policy. Shared dig-clear behavior, entity recovery, inspection, delays/time limits, and caller integration remain separate unchecked plan items.

## Verification

`tests/retry_policy.lua` checks retry success, exhaustion, terminal outcomes, default limits, and invalid policies. Lua 5.4.6 test execution and parse checks passed.
