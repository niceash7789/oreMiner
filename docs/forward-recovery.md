# Forward movement recovery

## Purpose

Recover safely when a forward move fails after the ordinary forward clear has run.

## Implemented behavior

`ForwardRecovery.run` retries a failed move only when the movement wrapper reports a physical `MOVE_FAILED`. It detects a solid obstruction and delegates to the existing attempt and time bounded `DigClear` operation. When no solid block is detected, it performs at most `entityRetries` attack/wait attempts. If supplied, the `warn` callback runs once immediately before the final entity attack/wait attempt; the active coordinator uses it to print a short request for nearby players to move. Exhaustion triggers one protected inspect: block names or tags identifying water/lava return `LIQUID`; absent, unsupported, malformed, or failed inspection returns `UNKNOWN_OBSTRUCTION`. Neither outcome attempts fluid handling. Repeated solid obstructions return `BLOCKED`. Fuel, persistence, and other movement denials propagate immediately without further world actions.

The active coordinator uses this helper in the shared movement adapter for forward, back, up, and down. Directional callbacks detect, dig, or attack only the target cell. Each checked movement attempt owns fuel admission and durable intent/pose commits. A typed directional attack failure stops recovery immediately.

## Public entry points

- `require("src.safety.forward_recovery").run(options)` accepts `move`, `detect`, optional `inspect`, `digClear`, `attack`, optional `warn`, `wait`, `maxMoveRetries`, and `maxEntityRetries` callbacks/limits.
- `require("src.config.defaults").safety` supplies `moveRetries`, `entityRetries`, and `retryDelay`.

## Invariants and assumptions

- Move retries and entity attempts are bounded to positive integer limits no greater than 64.
- A successful pose update remains the responsibility of the checked movement wrapper; failed movement does not update pose.
- Solid blocks are never handled as entities. Dig failures retain their typed result, including `UNBREAKABLE_BLOCK` and `BLOCKED`.
- An attack result is not treated as proof that the obstruction is gone; the turtle waits and retries checked movement.
- The warning fires only before the last configured entity attack/wait retry, once per recovery operation.
- Inspect is advisory and protected; no movement, digging, or plugging follows a liquid or unknown obstruction result.

## Dependencies and limitations

The helper depends on `src.safety.result` and injected callbacks. The coordinator supplies `DigClear` for solid blocks, `turtle.attack` for entity recovery, and `turtle.inspect` for best-effort classification. Modded fluid tags/names may not identify all liquids, which safely remain `UNKNOWN_OBSTRUCTION`. No in-world test was run.

## Verification

`tests/forward_recovery.lua` covers transient and persistent entities, solid block clearing and exhaustion, typed dig failure propagation, fuel-denial short-circuiting, liquid identification, and inspection failure fallback. `tests/dig_clear.lua` and `tests/active_baseline_wiring.lua` cover the existing clear policy and coordinator integration.
