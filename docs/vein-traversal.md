# Vein traversal

## Purpose

Mine a connected ore excursion without Lua recursion and return to its exact tunnel checkpoint through the same cleared cells.

## Implemented behavior

`VeinTraversal.run(checkpoint, ops, seedInverse)` performs iterative depth-first search with a coordinate-key visited set, a 64-block cap, and an 8-edge Manhattan-depth cap from the tunnel checkpoint. The caller has already dug and entered the seed ore; its move inverse is passed as `seedInverse` and is the first breadcrumb. It explores four forward headings plus up and down. Every discovered block adds an inverse movement and entry-facing breadcrumb. Child completion and abort unwind by popping breadcrumbs; failed inverse movement reports `VEIN_RETURN_BLOCKED`, and completion verifies checkpoint coordinates and facing. Inventory pressure stops discovery and unwinds before returning `INVENTORY_RETURN`.

The active coordinator in `src/branch_miner.lua` supplies the existing fuel-gated movement wrappers, inspect/dig callbacks, and inventory-pressure check. It starts an excursion only after successfully digging and entering the inspected seed ore block. Each adjacent inspected block independently passes through `OreClassifier.isOre` from `src/mining/ore_classifier.lua`; qualifying neighboring IDs join the same connected vein, while non-ore neighbors are not dug.

Return-path movement failures are propagated: vein inverse breadcrumbs stop with `VEIN_RETURN_BLOCKED`; the branch upper-scan ascent, per-step return, and descent stop the branch with `BRANCH_RETURN_MOVE_FAILED`; and `safeBack()` reports failure when its fallback turn or movement fails. Pose and known-route edges remain committed only by movement wrappers after the turtle API succeeds.

## Public entry points

- `require("src.mining.vein_traversal")`
- `VeinTraversal.run(checkpoint, ops)` returns `{ok, code, blocks}`. Callbacks are `pose`, `project(direction)`, `inspect(direction)`, `dig(direction)`, `move(direction)`, `turnRight()`, and `inventoryPressure()`.
- The coordinator's inspect callback returns the classifier result as its ore flag; it does not require equality with the seed ID.
- Physical action callbacks must report literal `true` on success. `project` returns the candidate world pose; the traversal commits visited coordinates only after movement succeeds.

## Invariants and assumptions

- The caller has already entered the seed ore block; `checkpoint` is the exact tunnel pose before that entry, and `seedInverse` reverses the seed movement.
- Horizontal movement is always performed after orienting the turtle through checked right turns. Breadcrumbs retain the entry facing so abort unwinds can restore the correct heading before moving back.
- The active movement wrappers enforce the current known-route fuel policy and update `pos` only on successful turtle movement.
- The traversal owns only local frontier, visited, and breadcrumb tables; it does not retain or persist excursion state.

## Dependencies and limitations

The module depends only on callback behavior supplied by its caller. Persistence, `POSITION_UNCERTAIN` intent journaling, cross-reboot resume, and reporting cap exhaustion to the operator remain unimplemented. A failed outward movement after digging stops with `VEIN_MOVE_FAILED` and does not fabricate a pose.

## Verification

Run `C:/Users/Game/AppData/Local/Programs/Lua/bin/lua.exe tests/vein_traversal.lua` from the repository root. The deterministic test covers a connected two-ID qualifying vein and a connected non-ore boundary, as well as DFS completion, exact checkpoint restoration, cap handling, inventory unwind, outward failure, and failed inverse `back`, `up`, and `down` movements.
