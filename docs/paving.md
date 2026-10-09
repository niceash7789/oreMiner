# Optional floor paving

## Purpose and behavior

Paving optionally places configured floor blocks below a cleared route cell. It is disabled by default. When enabled, `Paving.tryDown` considers only exact allowlisted IDs accepted by the shared inventory policy and consumes only stock above that item's retained quota. Fuel, torches, ores, unknown IDs, and explicitly protected IDs are never paving stock. Empty stock or a failed optional placement produces a warning at the coordinator; it does not stop the mining route.

## Public API

- `require("src.inventory.paving").tryDown(config, turtleApi, slotGuard, itemPolicy)` returns a typed result with `ok`, `code`, and `placed` fields.
- The active integration is `paveDown` in `src/branch_miner.lua`, called after successful forward tunnel movement.

## Invariants and assumptions

- Disabled mode returns before inventory reads, selection, or placement.
- Both selection and `placeDown` require literal `true`; the selected slot is restored through `SlotGuard` on all operation results.
- Aggregate counts determine available stock, so split stacks cannot defeat the retained quota.
- The mandatory cobblestone reserve remains independent of the paving flag and is enforced by `itemPolicy.mayConsumeForPaving`.

## Dependencies and limitations

Uses injected CC:Tweaked turtle APIs, `src.inventory.slot_guard`, and `src.config.item_policy`. Placement is opportunistic and only checks the API result; this module does not inspect the resulting floor block. Physical material behavior and route coverage need a controlled in-world test.

## Verification

Run `lua tests/inventory_paving.lua`, `tests/item_policy.lua`, `tests/config_loader.lua`, and `tests/active_baseline_wiring.lua`. These checks cover retained reserve, protected IDs, literal API success, default-off behavior, and coordinator integration. Physical material behavior and route coverage remain an operator check.
