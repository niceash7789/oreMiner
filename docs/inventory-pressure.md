# Inventory pressure

## Purpose and behavior

Trigger the existing return-and-unload path when occupied slots reach the configured pressure threshold. The default is 14 of 16 slots, leaving two slots of headroom for differently typed drops during unwind.

## Public entry points

- `require("src.inventory.pressure").occupiedSlots(turtleApi)` counts non-empty inventory slots.
- `require("src.inventory.pressure").slotCounts(turtleApi)` returns occupied and free slot counts across all 16 slots.
- `require("src.inventory.pressure").reached(turtleApi, threshold)` returns whether pressure is reached and the occupied count; invalid thresholds return a typed error as the second value.
- `src.config.defaults.inventory.returnThreshold` provides the default threshold (14); `autoConsolidate` defaults to true.
- `require("src.inventory.pressure_gate").beforeDig(pressureReached, serviceIfNeeded)` admits work only after an explicit clear pressure result or a completed service trip.

## Invariants and assumptions

- Slot counts come from `getItemCount` for all 16 turtle slots.
- Each non-empty slot counts once regardless of whether its stack is full or partial; free slots equal 16 minus occupied slots.
- Pressure triggers at `occupied >= threshold`; it does not claim that further digging is safe.
- `src.inventory.service` first consolidates compatible stacks, measures pressure, and routes a trigger through return and unload. During iterative vein exploration, each eligible adjacent ore edge is checked before digging; pressure stops exploration and the explicit breadcrumb stack unwinds to the vein entry pose before inventory service begins.

## Dependencies and limitations

The pressure module depends only on the injected CC:Tweaked turtle API and standard Lua. Consolidation is best effort, so incompatible or full stacks can remain separate. The service uses the existing checked movement and fuel-admission helpers. Pressure checks do not replace the independent fuel-to-home admission check.

The pressure gate fails closed with `INVENTORY_PRESSURE_CHECK_FAILED` if its probe throws or returns anything other than a literal boolean; it does not invoke service in that case. A service exception returns `INVENTORY_SERVICE_FAILED`.

## Verification

`tests/inventory_pressure.lua` verifies 13 versus 14 occupied slots using the configured threshold. `tests/inventory_pressure_gate.lua` connects that count to the pre-dig admission boundary: service completes before the dig at 14, and a failed service prevents the physical dig. `tests/vein_traversal.lua` uses the real pressure counter at 14 inside a seed excursion and verifies unwind before neighbor inspection or digging. Related service behavior is covered by `tests/inventory_service.lua` and `tests/inventory_mixed_partial_stacks.lua`. Run with the Lua 5.4 runtime documented in `docs/home-test.md`.
