# Strict project rules

## Scope

- V1 is a single ComputerCraft: Tweaked mining turtle. Do not add networking, fleet coordination, multi-turtle jobs, or controller code.
- Treat `MINER_PLAN.md` as the product specification. If code and plan conflict, stop and report the conflict instead of silently choosing.
- Implement only the explicitly assigned checklist item and its direct prerequisites. Avoid unrelated cleanup and feature creep.
- Do not mark a plan item complete unless its implementation exists and its relevant verification passed.

## Project documentation and dispatcher handoff

- Keep durable implementation notes in the repository's `docs/` folder. Create it if it does not exist.
- As each assigned feature is implemented, create or update the relevant focused document in `docs/` during the same change. Do not defer documentation to a later task.
- Keep docs small and scoped to one concern. Prefer files such as `docs/navigation.md`, `docs/fuel-and-return.md`, or `docs/inventory-service.md` over one large running diary.
- Each feature document must state its purpose, implemented behavior, public module/API entry points, important invariants and assumptions, dependencies, and current limitations.
- Add a short `docs/STATUS.md` dispatcher handoff note whenever implementation work changes the repository. Include the last completed checklist item, the next eligible unchecked item, files changed, verification performed or not performed, and any blocker or decision the next run must know.
- Treat `MINER_PLAN.md` as the authoritative backlog. Docs explain the current implementation; they must not silently change scope or redefine requirements.
- Before starting a checklist item, read `docs/STATUS.md` and the relevant feature doc if present. Update them before finishing the task.
- Do not copy the full plan or large source files into docs. Link to repository paths and summarize only what the next implementer needs.
- When a task is blocked, write the concrete blocker and the exact next action into `docs/STATUS.md`; do not mark the checklist item complete.

## Reference and active baseline

- Before implementing functionality, inspect the `reference/` folder for relevant existing code and proven patterns.
- Prefer adapting or reusing suitable implementations from `reference/` over writing equivalent functionality from scratch.
- Treat `reference/branch_miner_phase1.lua` as the read-only original. Do not modify, move, rename, or delete it.
- `src/branch_miner.lua` is the active writable copy. Modify it when the assigned checklist item changes its behavior or replaces one of its inline responsibilities with another module under `src/`.
- Progressively shorten `src/branch_miner.lua` into the high-level coordinator as configuration, navigation, mining, inventory, persistence, reporting, and other responsibilities move into focused modules.
- Preserve existing behavior when adapting reference code, make only the changes required for the assigned item, and avoid unnecessary refactoring.
- `MINER_PLAN.md` remains authoritative if reference code differs from the product specification; stop and report any conflict.

## Module and memory boundaries

- Keep each distinct behavior in its own small Lua module under `src/`; do not build a monolithic script.
- Split by responsibility: configuration, turtle movement, route/fuel policy, staircase, floor/branch traversal, ore/vein handling, inventory, chest service, lighting, persistence, errors, and status reporting.
- A module must not require unrelated feature modules. Load a module only at the point the feature is needed; avoid a startup loader that eagerly `require`s every module.
- Prefer small functions and explicit inputs/outputs. Keep transient scratch data local to the operation; do not retain large tables or duplicate state across modules.
- Keep persistent state limited to the fields needed to resume safely. Do not serialize caches, logs, or derived data.
- Keep optional behavior behind a narrow module boundary so disabled features are not loaded or run.
- Shared constants and result/error definitions belong in small dedicated modules. Avoid circular `require` dependencies.

## Safety and behavior

- Never assume a turtle move, turn, dig, drop, refuel, or placement succeeded. Check the API result and return a typed outcome.
- Update the saved pose only after a successful movement/turn. Preserve the plan's pending-action and `POSITION_UNCERTAIN` rules.
- Never start a movement unless the fuel policy proves the known route home plus reserve remains affordable.
- Return through recorded cleared routes. Do not dig shortcuts during return or invent coordinates when pose is uncertain.
- Bound retries, falling-block handling, vein traversal, and all loops that can encounter the world.
- Keep torches on the route-defined right side and preserve the specified left supply, right output, optional rear bulk chest layout.

## Lua and ComputerCraft compatibility

- Target the Lua version and APIs provided by the project's supported CC:Tweaked version; do not assume desktop Lua libraries or filesystem APIs exist.
- Keep modules usable with CC:Tweaked's `require` behavior and avoid dynamic code loading.
- Use descriptive names, consistent indentation, and comments for invariants or non-obvious movement geometry, not line-by-line narration.
- Configuration must be validated before the turtle moves or consumes inventory.

## Verification and change discipline

- For each assigned item, inspect the relevant plan section and the smallest set of related modules.
- Add focused tests or a deterministic fake-turtle test when behavior can be exercised without Minecraft. Keep test helpers separate from runtime modules.
- Run only the relevant checks for the assigned item; report checks that could not run.
- Keep changes narrow. Do not introduce dependencies, generated artifacts, binaries, or large data files without an explicit need.
- Preserve user changes. Never reset or overwrite unrelated files.

