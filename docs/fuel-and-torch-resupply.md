# Fuel and torch resupply

## Purpose and behavior

Restore enough internal fuel for the saved checkpoint's known-route round trip, one bounded work move, and the configured reserve, then pull torches toward the configured stock target and restore the physical emergency-fuel item quota from the verified left supply chest. The configured retained torch and fuel quantities are final onboard caps and restock targets (64 each by default, one stack). Surplus stacks are held temporarily in empty turtle slots while the bounded scan reaches later chest slots, then the excess is returned with verified drops before departure. Torch target is best effort; departure requires the separate minimum torch count. The bounded extractor supports fuel-first and torch-first chest ordering. Every pull is inspected: configured fuel and torches are retained as needed, while unrelated or malformed contents are returned after scanning. When stock is temporarily insufficient, inventory service remains checkpointed at base and repeats the bounded check every five seconds until both requirements are met. Missing chests and transfer faults stop for operator repair.

Before a new run leaves the surface, the coordinator faces and verifies the configured left supply chest, checks all carried fuel and torch stacks through the bounded resupply scan, and restores the original facing. Startup fuel covers the fixed surface entry and its return, reserve, and one work move. If fuel or required torches are temporarily short, it waits at the surface and repeats the check before any route movement.

Startup does not refuel toward an estimate for the entire mining job. The tank is filled only to the departure route commitment; later moves consume permitted onboard fuel only when the recorded route home plus reserve requires it. After scanning, resupply returns the exact excess above the aggregate coal or torch quota and verifies each slot count. This includes partial stacks. A chest with more preceding stacks than available turtle scratch slots or the configured pull limit can still require the operator to reorder or restock it.

## Public entry point

The first durable startup snapshot carries a surface-entry cursor. After a reboot during a fuel or torch wait, `miner resume` rechecks the left supply chest before admitting any route move.

- `require("src.inventory.resupply").run(options)` takes the turtle API, item policy, fuel target, torch target, minimum departure torch count, and optional pull limit. It validates finite non-negative integer quotas, a positive finite pull limit, and required API methods before calling the turtle; invalid input returns a structured error without changing selection or inventory. Valid calls return a structured result and restore the prior selected slot.
- `require("src.fuel.item_validation").verify(api, slot, config)` verifies that a slot contains a configured fuel item, selects it, and requires literal `true` from `refuel(0)` without consuming an item. Active route and automatic reserve refuelling use this check before `refuel(1)`.
- `require("src.fuel.resume_commitment").targetFuel(routeMoves, reserve, workStepMoves?)` validates and computes the resume fuel target; the default work step costs one move.
- `src/inventory/service.lua` invokes the injected resupply callback after output unloading and before persisting/resuming. `src/branch_miner.lua` derives the known checkpoint-to-origin distance and requires fuel for both that return and replay leg, the configured reserve, and one next work move before departure.

## Invariants and assumptions

- The service faces the exact configured supply chest before each resupply operation. Every pulled stack is inspected; only configured fuel IDs and `minecraft:torch` are used. Surplus and unrelated pulled items occupy temporary scratch slots until scanning ends, so dropping them cannot expose the same stack to the next `suck`. Returns are verified before the operation exits.
- A fuel item is consumed only when `refuel(0)` verifies it. The API must return literal `true`; truthy non-boolean values fail closed. Resupply additionally requires each consumed item to reduce its stack and increase reported fuel.
- Departure requires fuel for both route legs, one bounded work move, and reserve, plus at least `minimumTorches`. If the left chest is temporarily short, the coordinator stays at base and retries the durable service stage, without replaying the saved mining route. `miner resume` also accepts a saved supply-short service state after a reboot. Resupply pulls toward `torchTarget` while supply and capacity remain, but an exhausted chest or full inventory is acceptable when the minimum is already met.
- After filling the tank, resupply retains at most `inventory.fuelRetainedCount` items across configured fuel IDs. This onboard quota is separate from internal tank fuel and is restored during every base service. Resupply retains at most `inventory.torchRetainedCount` torches; excess torch stacks encountered while searching for fuel are returned to the supply chest.
- The onboard quotas are aggregate caps across slots at the end of each operation. A partial stack is reduced only by the excess amount, and each return is verified. The minimum departure torch count cannot exceed the retained torch quota.
- Supply pulls and the amount of mixed-chest scanning are finite. A failed return stops resupply. If the turtle runs out of empty scratch slots before reaching a needed category, it remains at base with a typed shortage result.

## Dependencies and limitations

Uses CC:Tweaked `suck`, `drop`, `refuel`, inventory, selected-slot, and fuel APIs plus `src/config/item_policy.lua` and `src/fuel/item_validation.lua`. Resume fuel assumes the shortest recorded origin/checkpoint path can be traversed in both directions; per-move route admission remains the final guard. Live chest ordering and multi-trip behavior still require a controlled in-world test.

## Verification

`tests/fuel_item_validation.lua` verifies configured-item checks, literal API success, and non-consuming `refuel(0)` behavior. `tests/resume_commitment.lua` covers round-trip, reserve, work-step, and invalid-input calculations. `tests/inventory_resupply.lua` covers both chest category orderings, fuel verification, best-effort torch target with minimum-count admission, emergency-fuel quota restoration (including intervening torch stacks), selected-slot restoration, absent fuel/insufficient torch results, and invalid numeric inputs rejected before turtle calls. `tests/inventory_service.lua` checks that base service invokes resupply before resuming, keeps its durable service stage after a supply shortage, and replays to the exact checkpoint once supplies become available. No in-world check was performed.

`tests/startup_coal_budget.lua` reaches the first floor-mining action with a finite tank and confirms the whole-job estimate consumes no coal. `tests/inventory_resupply.lua` also verifies an exact partial-stack coal return, four incidental coal stacks returned while searching for torches, and a chest that reoffers a dropped torch stack before later coal. Resupply and service checks passed with local Lua 5.4 on 2026-10-11; physical startup fuel and chest ordering remain an operator check.
