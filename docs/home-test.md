# Controlled gallery test

## Purpose

Give an operator a short, repeatable path through the software MVP's physical gates before running a full-size mine.

## Setup and assumptions

Install from the turtle shell using [in-game installation and pull](installation.md), then edit the generated `config.lua`. Use a replaceable, flat gallery in a CC:Tweaked world with coordinates visible, no protected blocks, no liquids, abundant fuel, and a backed-up world. Configure the smallest supported job: one floor, short main shaft, one shaft pair, short shaft length, and a low service threshold only if the configuration validator permits it. Start at the documented origin facing north. Put fuel and torches in the left supply chest, the ore/output chest on the right, and the optional bulk chest behind.

## Test sequence

1. Run `miner status`; verify it is read-only. Start the short job and confirm the turtle advances four blocks before descending.
2. Pause after a stair slice. Measure the 3-wide × 4-tall passage and centreline position; repeat through floor 1 and verify the landing is eight blocks below the surface. Confirm floor work returns to the landing before any next descent.
3. Mine a short main shaft and one left/right pair. Measure the 1×2 passages and the two solid rows between paired shafts. Confirm the final upper scan returns to origin.
4. Run a separate service job that reaches the configured inventory threshold. Observe output routing, fuel/torch refill, and exact cursor restoration. Repeat once with a missing or full required chest and verify a safe stop at base.
5. Place a small connected ore vein in a replaceable wall, then trigger inventory service during a larger vein. Confirm exact vein unwind before travel.
6. Force reboot at a committed tunnel checkpoint and during service; run `miner status` before `miner resume`. Confirm the cursor does not repeat or skip work. In software, all eight pre-slice stair cursors and the landing-carve cursor have named safe refusals, while an in-flight physical action remains uncertain. If rebooting during a stair sweep or landing carve, expect the matching safe refusal; do not manually move the turtle and then resume.
7. Finish Gate F only after the preceding checks: run a multi-trip ore job, force reboot between trips, resume, and confirm completion at origin with no duplicated or skipped route unit.

## Public entry points and dependencies

The operator commands are `miner`, `miner status`, and `miner resume`; see [persistence](persistence.md) and [runtime baseline](runtime-baseline.md). This procedure requires a CC:Tweaked world and the project's configured chest layout.

## Limitations

No physical test has been performed by this software workspace. Stair-sweep sub-action and landing-carve restart cursors are currently rejected safely. Run automated Lua checks from the repository root with `C:\Users\Game\AppData\Local\Programs\Lua\bin\lua.exe`; the compatible runtime may not be on PATH. Record measured outcomes and only check the corresponding `MINER_PLAN.md` gates after they pass.
