# Inventory pressure

## Purpose and behavior

Trigger the existing return-and-unload path when occupied slots reach the configured pressure threshold. The default is 14 of 16 slots, leaving two slots of headroom for differently typed drops during unwind.

## Public entry points

- `require("src.inventory.pressure").occupiedSlots(turtleApi)` counts non-empty inventory slots.
- `require("src.inventory.pressure").slotCounts(turtleApi)` returns occupied and free slot counts across all 16 slots.
- `require("src.inventory.pressure").reached(turtleApi, threshold)` returns whether pressure is reached and the occupied count; invalid thresholds return a typed error as the second value.
- `src.config.defaults.inventory.returnThreshold` provides the default threshold (14); `autoConsolidate` defaults to true.

## Invariants and assumptions

- Slot counts come from `getItemCount` for all 16 turtle slots.
- Each non-empty slot counts once regardless of whether its stack is full or partial; free slots equal 16 minus occupied slots.
- Pressure triggers at `occupied >= threshold`; it does not claim that further digging is safe.
- `src.inventory.service` first consolidates compatible stacks, measures pressure, and routes a trigger through return and unload. During iterative vein exploration, each eligible adjacent ore edge is checked before digging; pressure stops exploration and the explicit breadcrumb stack unwinds to the vein entry pose before inventory service begins.

## Dependencies and limitations

The pressure module depends only on the injected CC:Tweaked turtle API and standard Lua. Consolidation is best effort, so incompatible or full stacks can remain separate. The service uses the existing checked movement and fuel-admission helpers. Pressure checks do not replace the independent fuel-to-home admission check.

## Verification

`tests/inventory_pressure.lua` and `tests/inventory_service.lua` passed with the project Lua executable; service verification asserts consolidation precedes measurement. The active wiring fixture does not simulate a pressure-triggered vein unwind.
