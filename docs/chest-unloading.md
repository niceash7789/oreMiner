# Chest routing and verified drops

## Purpose and implemented behavior

Accept each configured base chest by exact block ID, preserve aggregate supply quotas, and route output by item ID. The base service verifies the required left supply and right primary-output chests. With `base.separateBulk=true`, it also requires the rear chest and sends only IDs in `supplies.bulkNames` there. It then sends every remaining non-supply item—including ores and unknown modded drops—to the right chest.

`Chest.unload` snapshots all 16 slots and allocates each retained quota across matching stacks in slot order. Every exact-count drop requires literal API success and the expected post-drop count; a partial transfer returns `CHEST_FULL` and stops service.

## Public API

- `Chest.acceptsBlock(blockId, baseConfig)` checks exact membership in `acceptedChestBlockIds`.
- `Chest.dropSlot(turtleApi, slot)` verifies a complete-slot drop.
- `Chest.dropSlotCount(turtleApi, slot, count)` verifies an exact requested count.
- `Chest.unload(turtleApi, itemConfig, predicate)` unloads matching excess while preserving quotas; without a predicate it targets the primary output.
- `Chest.unloadBulk(turtleApi, itemConfig)` targets configured bulk IDs only.

## Invariants and assumptions

- No substring or display-name chest matching is used.
- Quotas are totals by item ID across arbitrary slots.
- Fuel, torches, and the mandatory cobblestone reserve remain according to their quotas. Ores and unknown items have no implicit keep rule and route right.
- A successful partial transfer is not completion. Count mismatches stop the operation.
- Inventory service restores the original selected slot and canonical home facing.

## Dependencies and limitations

The module depends on the injected CC:Tweaked turtle API and item policy. Resupply from the left chest remains a separate backlog item. In-world chest-full and modded-container behavior has not yet been exercised.

## Verification

`tests/chest_policy.lua`, `tests/inventory_mixed_partial_stacks.lua`, and `tests/inventory_routing.lua` cover quotas, classification, side detection, error mapping, partial transfers, and restoration.
