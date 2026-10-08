# Inventory service

## Purpose and implemented behavior

Keep inventory accounting and service-trip policy outside branch, staircase, and vein pattern execution. The service evaluates occupied-slot pressure, checks the accepted output chest, unloads only verified excess while honoring configured item-ID quotas and protected-item policy, and returns to the saved mining pose. Vein traversal asks the service for pressure before a new dig; patterns request service at their existing checkpoints.

## Public entry points

- `require("src.inventory.service").new(dependencies)` creates a service with `pressureReached()` and `serviceIfNeeded()` operations.
- Dependencies are injected: turtle API, runtime/item configuration, pose getter, facing/movement callbacks, and report callbacks. The module keeps no inventory or pose copy.
- Accounting remains in `src.inventory.pressure` and `src.inventory.chest`; selected-slot preservation uses `src.inventory.slot_guard`.

## Invariants and assumptions

- Pressure uses the configured threshold (default 14 occupied slots).
- An unload trip returns through the existing cleared route and restores the saved coordinates and facing only through checked coordinator movement callbacks.
- Chest acceptance uses exact configured block IDs. Drops require verified API success and post-drop counts; aggregate retained quotas and protected items are handled by the existing item policy.
- The slot guard restores the selected slot after unloading, including helper failures.
- The service is single-turtle and synchronous; the coordinator owns live pose and persistent checkpoints.

## Dependencies and limitations

Depends on the injected CC:Tweaked turtle API and the pressure, chest, and slot-guard modules. The current baseline still uses the original single output-chest-at-start layout and coordinate-axis return trip; hierarchical multi-floor service routing remains future work. Invalid numerical configuration remains blocked by the unresolved branch-length 30/32 specification approval.

## Verification

`tests/inventory_service.lua`, `tests/inventory_pressure.lua`, `tests/chest_policy.lua`, `tests/inventory_slot_guard.lua`, `tests/persistence_state.lua`, `tests/return_move.lua`, `tests/known_route_fuel.lua`, `tests/fuel_policy.lua`, and `tests/active_baseline_wiring.lua` passed with the project Lua executable. Changed Lua files passed `luac.exe -p`.
