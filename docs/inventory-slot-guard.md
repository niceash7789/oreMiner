# Inventory selected-slot guard

## Purpose and behavior

Preserve the turtle's selected inventory slot while an inventory or fuel helper temporarily selects other slots. `SlotGuard.run` captures the current slot, executes one helper, and attempts restoration even when the helper raises an error. It reports slot-read, helper, and restoration failures with structured status codes; a helper's `false` return is retained as a normal value.

## Public entry point

- `require("src.inventory.slot_guard")`
- `SlotGuard.run(turtleApi, operation)` returns `{ ok = true, value = ... }` when the helper completed and the slot was restored, or `{ ok = false, code = ..., message = ..., retryable = false }` otherwise.

## Invariants and assumptions

- The supplied API has CC:Tweaked-compatible `getSelectedSlot()` and `select(slot)` functions.
- Restoration is accepted only when `select(originalSlot)` returns exactly `true`.
- The helper is synchronous and returns one value. The guard owns no persistent state and does not change the helper's inventory policy.

## Dependencies and limitations

The module depends only on the injected turtle API and Lua `pcall`. The active `src/branch_miner.lua` uses it around refuelling, paving selection, and unloading. Inventory consolidation, quota, verified routing, and full resupply workflows remain separate unchecked plan items.

## Verification

Run `lua tests/inventory_slot_guard.lua`. The deterministic test covers normal and false helper results, a thrown helper error, and a failed restoration.
