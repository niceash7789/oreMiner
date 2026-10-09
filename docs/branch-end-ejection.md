# Branch-end cobblestone ejection

## Purpose and implemented behavior

When rear bulk separation is disabled, remove only cobblestone above the mandatory backfill reserve at a successfully reached branch endpoint. `src/branch_miner.lua` invokes the operation after persisting the turnaround cursor and before climbing to the upper return pass.

## Public API

`require("src.inventory.branch_ejection").run(turtleApi, itemConfig)` consolidates compatible stacks, calculates aggregate cobblestone excess, performs bounded exact-count forward drops, and returns `EJECT_COMPLETE`, `EJECT_NOT_NEEDED`, or `EJECT_FAILED` with a cause.

## Invariants and assumptions

- Only `minecraft:cobblestone` is eligible; ores, unknown items, fuel, torches, and other bulk IDs are never world-dropped.
- The reserve comes from `inventory.retainedItems["minecraft:cobblestone"]` and applies whether paving is enabled or disabled.
- Every drop must return literal success and reduce the selected stack by exactly the requested count. The aggregate before/after delta is verified again at the end.
- The operation attempts at most one drop per inventory slot and restores the original selected slot.
- Rear bulk separation disables branch-end ejection.

## Dependencies and limitations

The module depends on inventory consolidation, quota policy, checked chest drops, and selected-slot guarding. It assumes the coordinator calls it while facing into the completed branch dead end. In-world validation of dropped-item placement remains outstanding.

## Verification

`tests/branch_ejection.lua` covers split stacks, reserve preservation, unrelated-item protection, no-excess behavior, partial-drop failure, and selected-slot restoration. `tests/active_baseline_wiring.lua` exercises the wired branch path.
