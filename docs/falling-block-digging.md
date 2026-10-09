# Falling-block digging

## Purpose

Bound clearing forward, above, or below the turtle when gravel, sand, or another block repeatedly falls into the same cell.

## Implemented behavior

`src/safety/dig_clear.lua` runs a shared detect/inspect/dig loop with both a per-block attempt cap and a global elapsed-time cap. When configured, it inspects the current block before each dig and reports that block ID and attempt number through `onBlock`. A new block identity resets the attempt count for that identity; repeated attempts against the same identity do not. The global attempt count remains available in the result, and the elapsed-time limit bounds an endless sequence of changing falling blocks. It returns `NO_BLOCK` when clear, `BLOCKED` when either bound expires while a block remains, `UNBREAKABLE_BLOCK` when a detected block cannot be dug, or `INVALID_DIG_CLEAR_POLICY` for invalid limits. Results report successful dig count. Each successful dig waits briefly for falling blocks to settle. The active miner applies the result to forward/up/down clearing and increments its mined-block count by successful digs.

## Public entry points

- `require("src.safety.dig_clear").run(options)` accepts `detect`, optional `inspect` and `onBlock`, `dig`, `now`, `maxAttempts`, `maxElapsed`, and optional `wait` callbacks.
- `require("src.config.defaults").safety` sets `digRetries = 12` and `digTimeLimit = 5` seconds.

## Invariants and assumptions

- Detection and dig APIs are injected, so the policy can be tested without Minecraft.
- The deadline is checked before and after detection and before each dig; a slow detection cannot turn a timed-out clear into success.
- A detected block must be dug successfully; otherwise the loop stops with `UNBREAKABLE_BLOCK`. Attempt or time exhaustion while the cell remains obstructed returns `BLOCKED`, matching the movement-recovery error contract.
- With inspection enabled, each consecutive block identity has its own `maxAttempts` allowance. Identity changes reset that allowance; the elapsed-time cap remains global. Without inspection, the original single-block attempt cap applies to the whole clear operation.
- If inspection is enabled, its block record must contain a string `name`; malformed or missing data stops with `INVALID_BLOCK_INSPECTION` before digging. The active caller maps this ID to the matching forward/up/down inspection API.
- CC:Tweaked `os.epoch("utc")` supplies elapsed wall time; each successful dig waits 0.5 seconds before reinspection.

## Dependencies and limitations

Pure Lua helper with no turtle dependency. It depends only on the shared result constructor and injected callbacks, and is used for the coordinator's forward/up/down clear functions. Other single-dig movement recovery paths are outside this bounded falling-block loop.

## Verification

`tests/dig_clear.lua` covers per-attempt identity reporting, malformed inspection, persistent same-block exhaustion, identity-change reset, and global attempt/time bounds. `luac -p` checks the helper and focused test.
