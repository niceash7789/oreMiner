# Inventory service

## Purpose and implemented behavior

Keep inventory accounting and service-trip policy outside branch, staircase, and vein pattern execution. At each existing pressure checkpoint the service best-effort consolidates compatible stacks, then compares occupied slots to `inventory.returnThreshold` (default 14). A reached threshold returns over checked known-clear edges, verifies the configured base chests, routes output, and restores the saved pose. Vein traversal checks pressure before a new dig; its caller services only after traversal has unwound.

## Public entry points

- `require("src.inventory.service").new(dependencies)` creates a service with `pressureReached()` and `serviceIfNeeded()` operations.
- Dependencies are injected: turtle API, runtime/item configuration, pose getter, facing/movement callbacks, and report callbacks. The module keeps no inventory or pose copy.
- `require("src.inventory.pressure").slotCounts(turtleApi)` returns occupied and free slot counts; `occupiedSlots` and `reached` expose the related pressure queries.
- `require("src.inventory.pressure").consolidate(turtleApi)` makes a best-effort pass merging compatible same-name stacks.
- Accounting remains in `src.inventory.pressure` and `src.inventory.chest`; selected-slot preservation uses `src.inventory.slot_guard`.

## Invariants and assumptions

- Pressure uses `inventory.returnThreshold`; configuration validation accepts integer values from 1 through 15. `inventory.autoConsolidate` defaults to true; setting it to false skips consolidation.
- Consolidation considers matching item names only as candidates. It trusts `transferTo` only when source decrease and target increase match, compacts later slots into earlier slots without reversing progress, and leaves incompatible NBT variants untouched.
- Consolidation is best-effort; incompatible or full target pairs may remain split. It restores the previously selected slot and reports verified total transferred.
- An unload trip returns through the existing cleared route and restores the saved coordinates and facing only through checked coordinator movement callbacks.
- Chest acceptance uses exact configured block IDs. Missing sides return `NO_SUPPLY_CHEST`, `NO_OUTPUT_CHEST`, or `NO_BULK_CHEST`. Partial acceptance returns `CHEST_FULL`; other drop faults return `UNLOAD_FAILED`.
- Configured bulk IDs route rear only when `base.separateBulk=true`. All remaining excess, including ores and unknown items, routes right.
- `inventory.retainedItems["minecraft:cobblestone"]` protects the configurable mandatory main-shaft backfill reserve across arbitrary slots, regardless of paving state. Unloading drops only cobblestone above this reserve.
- The slot guard restores the selected slot after unloading, including helper failures.
- The service is single-turtle and synchronous; the coordinator owns live pose and persistent checkpoints.

## Dependencies and limitations

Depends on the injected CC:Tweaked turtle API and the pressure, chest, and slot-guard modules. Existing coordinator checkpoints are wired; stairs/floors are not implemented. The baseline's coordinate-ordered return is valid only for its current main/branch geometry; hierarchical multi-floor routing remains future work. Refuelling and torch restocking from the verified left chest remain separate backlog items.

## Verification

`tests/inventory_pressure.lua`, `tests/inventory_service.lua`, `tests/inventory_mixed_partial_stacks.lua`, and `tests/numeric_validation.lua` passed. `luac.exe -p` passed for changed Lua files. The service test verifies consolidation precedes pressure measurement. No in-world verification was performed.
