# Chest routing and verified drops

## Purpose and implemented behavior

Accept each configured base chest by exact block ID, preserve aggregate supply quotas, and route output by item ID. The base service verifies the required left supply and right primary-output chests. With `base.separateBulk=true`, it also requires the rear chest and sends only IDs in `supplies.bulkNames` there. It then sends every remaining non-supply item—including ores and unknown modded drops—to the right chest. Before unloading, the service travels from the exact current pose to surface home using the coordinator's recorded-route callback; afterward it travels back to that exact pose and facing.

When bulk separation is disabled, the service does not inspect or require a rear chest. Every non-retained item remaining at base, including residual cobblestone, goes to the right output chest. Routine excess cobblestone ejection is a separate completed-branch-end operation.

`Chest.unload` snapshots all 16 slots and allocates each retained quota across matching stacks in slot order. Every exact-count drop requires literal API success and the expected post-drop count; a partial transfer returns `CHEST_FULL` and stops service.

## Public API

- `Chest.acceptsBlock(blockId, baseConfig)` checks exact membership in `acceptedChestBlockIds`.
- `Chest.dropSlot(turtleApi, slot)` verifies a complete-slot drop.
- `Chest.dropSlotCount(turtleApi, slot, count)` verifies an exact requested count.
- `Chest.unload(turtleApi, itemConfig, predicate)` unloads matching excess while preserving quotas; without a predicate it targets the primary output.
- `Chest.unloadBulk(turtleApi, itemConfig)` targets configured bulk IDs only.
- `InventoryService.new(deps)` requires a `travel(targetPose)` callback for unload trips; the callback must enforce known-route, fuel, pose, and durable-action checks.

## Invariants and assumptions

- No substring or display-name chest matching is used.
- Quotas are totals by item ID across arbitrary slots.
- Fuel, torches, and the mandatory cobblestone reserve remain according to their quotas. Ores and unknown items have no implicit keep rule and route right.
- A successful partial transfer is not completion. Count mismatches stop the operation.
- Inventory service restores the original selected slot and canonical home facing.
- Service travel uses recorded cleared route edges only; missing route or travel failure stops service before chest interaction or return-to-work.

## Dependencies and limitations

The module depends on the injected CC:Tweaked turtle API, item policy, and a checked route-travel callback supplied by the active coordinator. The coordinator uses `RouteHome` with target poses and its persisted motion wrapper. Durable trip stages, left-chest refuelling/torch resupply, and known-route replay are implemented. Live chest ordering/content, chest-full/modded-container behavior, and multi-trip reliability remain in-world checks.

## Verification

`tests/chest_policy.lua`, `tests/inventory_mixed_partial_stacks.lua`, `tests/inventory_routing.lua`, `tests/inventory_service.lua`, and `tests/service_route.lua` cover quotas, classification, side detection, error mapping, partial transfers, known-route travel delegation, checkpoint ordering, service replay, and pose/slot restoration. `tests/inventory_service.lua` verifies bulk-disabled ore, unknown, gravel, and excess-cobblestone routing to the right chest while preserving retained quotas and requiring no rear chest; missing left, right, and configured rear chests return their specific codes and stop at base without replaying the mining route. It also verifies a rejected full output chest stops service at base. `tests/branch_ejection.lua` covers the branch-end cobblestone rule. No in-world check was performed.
