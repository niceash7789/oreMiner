# Fuel and torch resupply

## Purpose and behavior

Restore enough internal fuel for the saved checkpoint's known-route round trip, one bounded work move, and the configured reserve, then pull torches toward the configured stock target and restore the physical emergency-fuel item quota from the verified left supply chest. The configured retained torch and fuel quantities are hard onboard caps as well as restock targets (64 each by default, one stack); incidental torch stacks encountered while searching for fuel are returned when they exceed the torch cap. Torch target is best effort; departure requires the separate minimum torch count. The bounded extractor supports fuel-first and torch-first chest ordering and stops on unsupported items, failed transfers, absent fuel, or an unmet minimum quota.

## Public entry point

- `require("src.inventory.resupply").run(options)` takes the turtle API, item policy, fuel target, torch target, minimum departure torch count, and optional pull limit. It validates finite non-negative integer quotas, a positive finite pull limit, and required API methods before calling the turtle; invalid input returns a structured error without changing selection or inventory. Valid calls return a structured result and restore the prior selected slot.
- `require("src.fuel.item_validation").verify(api, slot, config)` verifies that a slot contains a configured fuel item, selects it, and requires literal `true` from `refuel(0)` without consuming an item. Active route and automatic reserve refuelling use this check before `refuel(1)`.
- `require("src.fuel.resume_commitment").targetFuel(routeMoves, reserve, workStepMoves?)` validates and computes the resume fuel target; the default work step costs one move.
- `src/inventory/service.lua` invokes the injected resupply callback after output unloading and before persisting/resuming. `src/branch_miner.lua` derives the known checkpoint-to-origin distance and requires fuel for both that return and replay leg, the configured reserve, and one next work move before departure.

## Invariants and assumptions

- The service faces the exact configured supply chest before each resupply operation; the chest contract allows configured fuel IDs and `minecraft:torch` only.
- A fuel item is consumed only when `refuel(0)` verifies it. The API must return literal `true`; truthy non-boolean values fail closed. Resupply additionally requires each consumed item to reduce its stack and increase reported fuel.
- Departure requires fuel for both route legs, one bounded work move, and reserve, plus at least `minimumTorches`; failure leaves the turtle at base. If the left chest cannot supply the minimum, resupply returns `NO_TORCHES` and inventory service does not travel back to the saved mining checkpoint. Resupply pulls toward `torchTarget` while supply and capacity remain, but an exhausted chest or full inventory is acceptable when the minimum is already met.
- After filling the tank, resupply retains at most `inventory.fuelRetainedCount` items across configured fuel IDs. This onboard quota is separate from internal tank fuel and is restored during every base service. Resupply retains at most `inventory.torchRetainedCount` torches; excess torch stacks encountered while searching for fuel are returned to the supply chest.
- Supply pulls and the amount of mixed-chest scanning are finite. Unsupported items are returned to the chest only after a verified drop.

## Dependencies and limitations

Uses CC:Tweaked `suck`, `drop`, `refuel`, inventory, selected-slot, and fuel APIs plus `src/config/item_policy.lua` and `src/fuel/item_validation.lua`. Resume fuel assumes the shortest recorded origin/checkpoint path can be traversed in both directions; per-move route admission remains the final guard. Live chest ordering and multi-trip behavior still require a controlled in-world test.

## Verification

`tests/fuel_item_validation.lua` verifies configured-item checks, literal API success, and non-consuming `refuel(0)` behavior. `tests/resume_commitment.lua` covers round-trip, reserve, work-step, and invalid-input calculations. `tests/inventory_resupply.lua` covers both chest category orderings, fuel verification, best-effort torch target with minimum-count admission, emergency-fuel quota restoration (including intervening torch stacks), selected-slot restoration, absent fuel/insufficient torch stops, and invalid numeric inputs rejected before turtle calls. `tests/inventory_service.lua` checks that base service invokes resupply before resuming, replays an interrupted trip from base to the exact checkpoint, and stays at base with `NO_TORCHES` when the departure minimum cannot be met. No in-world check was performed.
