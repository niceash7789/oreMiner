# Navigation and storage boundaries

## Purpose and implemented behavior

Keep route execution and inventory policy usable by any future local work domain while V1 continues to run one sequential turtle. Navigation modules receive checked movement, turn, clear, lighting, and checkpoint callbacks. Inventory modules own pressure, chest routing, and resupply policy; they receive the live pose, route, travel, and persistence operations they need from the coordinator. Neither side selects work by a worker role or imports the other side's policy.

## Public entry points

- `require("src.navigation.stair_slice").descend(options)` and `require("src.navigation.stair_route").descend(options)` compose a route through explicit callbacks.
- `require("src.inventory.service").new(dependencies)` exposes pressure checks, service trips, and interrupted-trip replay using injected dependencies.
- `src/branch_miner.lua` is the single sequential composition point for the active runtime.

## Invariants and assumptions

- Navigation owns route geometry and requires structured checked outcomes; the coordinator owns physical intent, pose commits, route fuel admission, and persistence.
- Inventory owns item/chest policy but does not move the turtle directly; travel and facing are supplied by the coordinator.
- Runtime remains one turtle and one active work unit. These module seams do not create independent jobs or scheduling.

## Dependencies and limitations

Navigation modules depend on pose, action-stack, route, and result contracts. Inventory service depends on pressure, chest, slot-guard, and resupply modules. The coordinator supplies CC:Tweaked APIs and composes the services. A role-specific executor or multi-turtle behavior is outside V1.

## Verification

`tests/navigation_stair_slice.lua`, `tests/inventory_service.lua`, `tests/service_route.lua`, and `tests/active_baseline_wiring.lua` exercise the callback boundary and active composition. No in-world verification is implied.
