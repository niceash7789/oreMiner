# Runtime baseline

## Purpose

Keep the original phase-one miner as a reference while a writable copy serves as the active executable baseline and the `MINER_PLAN.md` checklist incrementally separates and corrects its behavior.

## Implemented behavior

The root `miner.lua` resolves `src/branch_miner.lua` relative to its own installed location and executes it in a CC:Tweaked-compatible Lua environment. It forwards all shell arguments so `miner status`, `miner home`, and `miner resume` reach the coordinator. When native `require` is absent, the launcher supplies a repository-relative module loader backed by `fs.open` and `load`, with module caching and circular-load rejection. This supports the active coordinator and its `config` load without changing source modules. It fails before loading when required turtle, clock, filesystem, shell, or Lua compile APIs are unavailable. Runtime failures from the active program are reported with entry-point context.

`reference/branch_miner_phase1.lua` is the preserved original. `src/branch_miner.lua` is its writable working copy. A worker implementing a checklist item should modify the relevant active routine directly when needed, extract its distinct responsibility into the appropriate focused module under `src/`, correct the plan-listed defects in that slice, test it, and replace the inline logic with a narrow module call. As extraction proceeds, `src/branch_miner.lua` should become a short high-level coordinator.

Completed modules are wired immediately when they replace behavior the active baseline already executes. Foundational geometry may remain unwired only when a later phase must first provide its required state; that deferred integration point is recorded in the focused feature doc and dispatcher handoff.

## Public entry point

- Run `miner.lua` on a CC:Tweaked mining turtle with the repository directory structure intact. Supported recovery command names are `status` and `resume`.
- See [in-game installation and pull](installation.md) for the test bootstrap and manual update command.

## Invariants and assumptions

- `reference/branch_miner_phase1.lua` remains the read-only original for comparison.
- `src/branch_miner.lua` is the active writable copy. It loads the validated root `config.lua`, shows a read-only summary/confirmation, and retains the current `main()` call.
- Paths are resolved from `shell.getRunningProgram()`, so the launcher does not depend on the shell's current directory.
- This wiring is migration scaffolding, not evidence that any unchecked plan defect has been corrected.
- `MINER_PLAN.md` remains authoritative for the behavior of every migrated module.

## Dependencies and current limitations

The launcher depends on CC:Tweaked's `turtle`, `fs`, `shell`, `os.epoch`, `load`, and `setmetatable` APIs. Native `require` is optional; the fallback loader resolves module names from the installation root, caches returned values, and rejects circular dependencies. Configuration is file-backed and validated, but the active coordinator does not yet run the isolated surface-entry/stairs modules or the later multi-floor phase machine. Do not treat this baseline as V1-complete or safe for unattended operation.

## Verification

Run `lua tests/miner_entrypoint.lua` with Lua 5.4. The test supplies deterministic fake CC APIs and verifies path resolution, active-copy loading, command-argument forwarding, missing-file failure, and rejection on a non-turtle computer. It does not execute the miner or move a turtle.
