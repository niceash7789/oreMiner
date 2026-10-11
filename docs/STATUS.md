# Implementation status

- Current scope: single-turtle MVP in `MINER_PLAN.md`; NEXT/LATER/EXPERIMENTAL and fleet work remain excluded.
- Last completed item: cap base resupply at one configured stack of torches and one configured stack of coal; excess torches encountered while looking for fuel return to the supply chest. Focused quota coverage was added. Previous service-resume fix remains in the working tree.
- Next eligible item: mock 15th/16th-slot growth during vein unwind and prove return uses only the cleared route; then continue remaining software-verifiable MVP rows in plan order.
- Files changed this run: `src/inventory/resupply.lua`, `tests/inventory_resupply.lua`, `docs/fuel-and-torch-resupply.md`, and this handoff, alongside prior resume fix files.
- Verification (2026-10-11): `git diff --check` passed. Lua tests and syntax checks remain unavailable because Lua and luac are not installed/on PATH. `tests/inventory_resupply.lua` adds a mixed-order one-stack cap case; run it once a Lua 5.4 runtime is available.
- Blocker/decision: verify resupply tests and syntax with Lua 5.4, then confirm in-world that extra torches are returned and the turtle leaves with no more than the configured coal/torch quota. The defaults are 64 each.
- Operator steps: follow `docs/home-test.md` in a backed-up replaceable gallery. Verify chest layout, four-block entry, stair and landing geometry, paired shafts and exact return, service/chest failures, vein unwind, and reboot recovery. For Gate F, finish a multi-trip ore job, force reboot between service trips, run `miner status` then `miner resume`, and verify exact completion at origin with no duplicated or skipped work. Record outcomes before checking physical gates.
