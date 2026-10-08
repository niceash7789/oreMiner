# Falling-block digging

## Purpose

Bound clearing forward, above, or below the turtle when gravel, sand, or another block repeatedly falls into the same cell.

## Implemented behavior

`src/safety/dig_clear.lua` runs a shared detect/dig loop with both an attempt cap and elapsed-time cap. It returns typed outcomes (`CLEARED`, `DIG_ATTEMPTS_EXHAUSTED`, `DIG_TIME_EXHAUSTED`, `UNBREAKABLE_BLOCK`, or `INVALID_DIG_CLEAR_POLICY`) and reports successful dig count. Each successful dig waits briefly for falling blocks to settle. The active miner applies the result to forward/up/down clearing and increments its mined-block count by successful digs.

## Public entry points

- `require("src.safety.dig_clear").run(options)` accepts `detect`, `dig`, `now`, `maxAttempts`, `maxElapsed`, and optional `wait` callbacks.
- `require("src.config.defaults").safety` sets `digRetries = 12` and `digTimeLimit = 5` seconds.

## Invariants and assumptions

- Detection and dig APIs are injected, so the policy can be tested without Minecraft.
- The deadline is checked before and after detection and before each dig; a slow detection cannot turn a timed-out clear into success.
- CC:Tweaked `os.epoch("utc")` supplies elapsed wall time; each successful dig waits 0.5 seconds before reinspection.

## Dependencies and limitations

Pure Lua helper with no turtle dependency. It is used for the coordinator's shared forward/up/down clear functions. Other single-dig movement recovery paths are outside this bounded falling-block loop. Block identity reporting and resetting attempts when observed block identity changes remain separate unchecked plan items.
