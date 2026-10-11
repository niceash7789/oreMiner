# Controlled gallery test

## Purpose

Give an operator a short, repeatable path through the software MVP's physical gates before running a full-size mine.

## Setup and assumptions

Install from the turtle shell using [in-game installation and pull](installation.md), then edit the generated `config.lua`. Use a replaceable, flat gallery in a CC:Tweaked world with coordinates visible, no protected blocks, no liquids, abundant fuel, and a backed-up world. Configure the smallest supported job: one floor, one pair per main side, short shaft length, and a low service threshold only if the configuration validator permits it. Start at the documented origin facing north. Put fuel and torches in the left supply chest, the ore/output chest on the right, and the optional bulk chest behind.

## Test sequence

1. Run `miner status`; verify it is read-only. Start the short job and confirm the turtle advances four blocks before descending.
2. Pause after a stair slice. Measure the 3-wide × 4-tall passage and centreline position; repeat through floor 1 and verify the landing is `mining.stairStepsPerFloor + mining.firstFloorDepthOffset` blocks below the surface (four in the tracked example). Confirm later floors are separated by `mining.stairStepsPerFloor`, and floor work returns to each landing before the next descent. Run a separate short job with a nonzero offset to verify the deeper first landing and exact return.
3. Mine the right main shaft and its left/right pair, return to the exact landing centre, then mine the mirrored left main shaft and its own left/right pair. Measure all 1×2 passages and the two solid rows between paired shafts. Confirm the left pass returns to the landing before the floor completes and the final route returns to origin.
   In a separate short run, place a replaceable block in the upper shaft lane after its outbound pass. Verify the turtle digs that cell, retries the same edge, and finishes at origin. Repeat on a recorded stair return cell and verify it stays on the centreline. A protected or unbreakable block should produce a safe stop.
4. Run a separate service job that reaches the configured inventory threshold. Observe output routing, fuel/torch refill, and exact cursor restoration. Repeat once with a missing or full required chest and verify a safe stop at base.
5. Place a small connected ore vein in a replaceable wall, then trigger inventory service during a larger vein. Confirm exact vein unwind before travel.
6. Force reboot at a committed tunnel checkpoint and during service. Verify `/startup/oreminer.lua` launches `miner resume` automatically and the cursor does not repeat or skip work. For a manual diagnosis, run `miner status` after the boot attempt. In software, pre-slice stair cursors through the configured interval and the landing-carve cursor have named safe refusals, while an in-flight physical action remains uncertain. If rebooting during a stair sweep or landing carve, expect the matching safe refusal; do not manually move the turtle and then resume. Also reboot with a pending physical action and confirm an automatic `POSITION_UNCERTAIN` refusal with no movement.
7. Finish Gate F only after the preceding checks: run a multi-trip ore job, force reboot between trips, resume, and confirm completion at origin with no duplicated or skipped route unit.

## Public entry points and dependencies

The operator commands are `miner`, `miner status`, and `miner resume`; see [persistence](persistence.md) and [runtime baseline](runtime-baseline.md). This procedure requires a CC:Tweaked world and the project's configured chest layout.

## Limitations

No physical test has been performed by this software workspace. Stair-sweep sub-action and landing-carve restart cursors are currently rejected safely. Run automated Lua checks from the repository root with `C:\Users\Game\AppData\Local\Programs\Lua\bin\lua.exe`; the compatible runtime may not be on PATH. Record measured outcomes and only check the corresponding `MINER_PLAN.md` gates after they pass.
