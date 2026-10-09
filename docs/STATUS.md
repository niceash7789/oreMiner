# Implementation status

- Current scope: single-turtle MVP in `MINER_PLAN.md`; NEXT/LATER/EXPERIMENTAL and fleet work remain excluded.
- Last completed item: missing required supply/output/rear chest behavior; `tests/inventory_service.lua` verifies side-specific errors and safe stop at base without replaying the mining route.
- Next eligible item: add deterministic software coverage for excess cobblestone ejection at completed shaft dead ends with rear bulk routing disabled, then continue software-verifiable MVP rows in plan order.
- Files changed this run: `tests/inventory_service.lua`, `MINER_PLAN.md`, `docs/chest-unloading.md`, and `docs/STATUS.md`.
- Verification (2026-10-09): Lua tests and `luac -p` were attempted for `tests/inventory_service.lua`, `tests/chest_policy.lua`, `tests/service_route.lua`, `src/inventory/service.lua`, and `src/inventory/chest.lua`, but neither `lua` nor `luac` is installed or on PATH in this run. No test result is claimed. No physical checks were performed.
- Blocker/decision: this run's environment has no Lua runtime/compiler and no Minecraft/CC:Tweaked world or turtle. Re-run the focused Lua checks when Lua is available. Physical chest acceptance and Gate F remain open. Mid-slice stair-sweep and landing-carve resume remains intentionally fail-closed.
- Operator steps: follow `docs/home-test.md` in a backed-up replaceable gallery. Verify chest layout, four-block entry, stair and landing geometry, paired shafts and exact return, service/chest failures, vein unwind, and reboot recovery. For Gate F, finish a multi-trip ore job, force reboot between service trips, run `miner status` then `miner resume`, and verify exact completion at origin with no duplicated or skipped work. Record outcomes before checking physical gates.
