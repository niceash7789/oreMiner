# Chest acceptance and verified drops

## Purpose and behavior

Accept the configured output chest by exact block ID and verify each inventory drop before continuing. The default accepted IDs are `minecraft:chest` and `minecraft:trapped_chest`; modded chest IDs can be added to `base.acceptedChestBlockIds` in `src/config/defaults.lua`.

`src/inventory/service.lua` checks the block behind the starting position against that allowlist before unloading. `Chest.unload(turtleApi, itemConfig)` scans all 16 slots, computes retention by item ID across stacks, and drops only the excess from each eligible item. Protected fuel, torches, ores, unknown items, and configured protected items remain untouched. Each exact-count drop requires literal API success and the expected post-drop count; partial transfers and API failures stop the unload.

## Public entry points

- `require("src.inventory.chest").acceptsBlock(blockId, baseConfig)` checks exact membership in `acceptedChestBlockIds`.
- `require("src.inventory.chest").dropSlot(turtleApi, slot)` returns `{ ok, code, ... }`; failure codes include `DROP_SELECT_FAILED`, `DROP_FAILED`, `DROP_NOT_VERIFIED`, `CHEST_FULL`, and `DROP_COUNT_UNAVAILABLE`.
- `require("src.inventory.chest").unload(turtleApi, itemConfig)` returns `{ ok, code, retained }`, preserving configured aggregate quotas across all slots.
- `require("src.inventory.chest").dropSlotCount(turtleApi, slot, count)` verifies an exact requested excess drop.
- `src.config.defaults.base.acceptedChestBlockIds` provides the default block allowlist.
- `src.config.defaults.inventory.retainedItems` provides per-item quantity quotas; paving retention remains conditional on paving being enabled.

## Invariants and assumptions

- Block names are treated as exact IDs. No substring or display-name matching is used.
- A non-empty slot is complete only when `turtle.drop()` returns literal `true` and its post-drop count is zero.
- A `true` result with items remaining returns `CHEST_FULL`; a `false` result remains `DROP_FAILED` even if the observed count reached zero.
- Quotas are aggregate item-ID counts allocated in slot order; no slot receives privileged status.
- Fuel, torches, ores, unknown IDs, and configured protected IDs retain the existing protected-item policy and are never dropped by quota processing.
- The inventory service wraps unloading in `SlotGuard.run` so the selected slot is restored after the operation.

## Dependencies and limitations

The chest module uses the injected CC:Tweaked turtle API, item policy, and standard Lua. The inventory service covers the active baseline's single output chest check and unload loop. The planned left/right/rear chest routing and verified world ejection remain separate backlog items. Deterministic tests validate API/count handling without a Minecraft world. The active wiring fixture uses spacing 1, so the miner ends at the first main-tunnel junction `(0,0,-1,facing=0)`; its assertion reflects that current baseline route.

## Verification

`tests/active_baseline_wiring.lua`, `tests/chest_policy.lua`, `tests/item_policy.lua`, `tests/inventory_slot_guard.lua`, and `tests/inventory_pressure.lua` passed with `C:/Users/Game/AppData/Local/Programs/Lua/bin/lua.exe`. Syntax checks passed with `C:/Users/Game/AppData/Local/Programs/Lua/bin/luac.exe -p` for changed Lua and fixture files.
