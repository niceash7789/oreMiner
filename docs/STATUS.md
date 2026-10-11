# Implementation status

- Latest user-directed change: fuel/torch resupply now returns and skips unrelated or malformed supply-chest stacks, continuing its bounded scan for configured fuel and torches. `tests/inventory_resupply.lua` includes interleaved unwanted contents. Lua checks are pending in this environment; no in-world chest check was performed.

- Latest user-directed change: temporary fuel or torch shortages at the supply chest now leave the durable service checkpoint at base and retry every five seconds; restocking resumes the saved route. Supply-short service states remain eligible for `miner resume` after reboot. Focused service and recovery tests were updated; run them with Lua 5.4 when available. No physical release check was performed.

- Current scope: single-turtle MVP in `MINER_PLAN.md`; NEXT/LATER/EXPERIMENTAL and fleet work remain excluded.
- Last changed item: user-directed stairs clearance update to 3-wide × 4-tall; plan, config validation, slice geometry, focused tests, and operator docs were updated. This item is not marked complete until the focused Lua checks pass.
- Next eligible item: run `tests/navigation_stair_slice.lua`, `tests/numeric_validation.lua`, `tests/stair_route.lua`, and `tests/active_baseline_wiring.lua` with Lua 5.4, then resume the prior MVP backlog item: mock 15th/16th-slot growth during vein unwind and prove return uses only the cleared route.
- Files changed for the stair update: `MINER_PLAN.md`, `src/config/numeric_validation.lua`, `src/navigation/stair_slice.lua`, `tests/navigation_stair_slice.lua`, `tests/numeric_validation.lua`, `docs/stairs.md`, `docs/lighting.md`, `docs/home-test.md`, and `docs/STATUS.md`. Other modified working-tree files were already present and were not changed for this update.
- Verification (2026-10-11): `git diff --check` passed using the bundled Git executable. Focused Lua tests and syntax checks were not run because Lua/luac are unavailable in the environment.
- Blocker/decision: verify the new twelve-cell slice and fixed height validation with Lua 5.4. Then confirm in-world that the stair passage measures three blocks wide and four blocks tall, including the extra upper row on both side columns; existing landing depths and offsets should remain unchanged.
- Operator steps: follow `docs/home-test.md` in a backed-up replaceable gallery. Verify chest layout, four-block entry, stair and landing geometry, paired shafts and exact return, service/chest failures, vein unwind, and reboot recovery. For Gate F, finish a multi-trip ore job, force reboot between service trips, run `miner status` then `miner resume`, and verify exact completion at origin with no duplicated or skipped work. Record outcomes before checking physical gates.

## User-directed operator home command

- Implemented `miner home`: from the shell, it pauses the saved run, unwinds a saved vein, returns over recorded stairs/routes, and stores an at-base service checkpoint so `miner resume` can return to the saved work cursor. It asks for no confirmation. The current synchronous mining process must first be interrupted at the turtle prompt with Ctrl+T.
- Updated files: `src/branch_miner.lua`, `src/persistence/checkpoint.lua`, `src/persistence/state.lua`, `src/persistence/recovery.lua`, `src/persistence/startup.lua`, `tests/recovery_status.lua`, `tests/persistence_state.lua`, `docs/home-command.md`, `docs/status-reporting.md`, `docs/runtime-baseline.md`, and this handoff.
- Verification for this item: bundled Git `diff --check` passed. Focused Lua tests and syntax checks were not run because this shell cannot find `lua` or `luac`. Added focused dispatch and paused-state recovery assertions.
- Next action for this item: run `tests/recovery_status.lua` and `tests/persistence_state.lua` plus Lua 5.4 syntax checks when available; then verify home return, vein unwind, and reboot recovery in a backed-up in-world setup. Do not check off the `miner home` plan row until focused verification passes.
