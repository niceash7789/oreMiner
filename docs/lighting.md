# Route-frame lighting

## Purpose and implemented behavior

Provide a small helper for placing a torch in the right cell of a route's fixed outbound frame. `src/lighting/right_wall.lua` turns to the route-defined right, clears the target niche with a bounded caller-supplied dig operation by default, places the selected torch, and restores the starting facing through checked turns. Callers may set `alreadyClear=true` to place into a previously cleared cell without invoking any dig callback; stair lighting uses this path for the adjacent right-column passage cell. Callers may provide `poseNow`; when present, its committed live pose is compared with the starting pose after placement and facing restoration, and coordinate drift fails with `LIGHTING_POSE_MISMATCH`. The active coordinator supplies this check. It applies tunnel cadence on floor main-shaft cells and stair cadence inside the cleared stair passage. The final slice before each landing is excluded. Successful placements are durably recorded by floor, route, and distance key, so restarts skip completed locations.

## Public entry points

- `require("src.lighting.right_wall").placeRight(ops)` accepts a committed pose, outbound facing, checked `turn`, and structured-result `place`; it also accepts a structured-result `dig` callback unless `alreadyClear=true`. Optional `poseNow()` verifies exact live pose restoration.
- `require("src.lighting.right_wall").rightSide(pose, outboundFacing)` returns the adjacent route-defined right cell as a pose whose `facing` is the absolute right heading, independent of current facing; invalid frames return `LIGHTING_INVALID_FRAME`.
- `src/navigation/stair_slice.lua` accepts optional `placeOuterRightTorch(pose)` after all passage cells are clear and before the downward step.
- `src/navigation/stair_route.lua` accepts `stairTorchInterval` and `placeStairTorch(pose, step)`; cadence uses one-based slice distance and skips the final slice.
- `src/branch_miner.lua` selects a configured torch item under the inventory slot guard and calls the helper at stair, main-shaft, and branch intervals. Branch placement uses the immutable outbound heading from the branch route; stair placement uses the slice's recorded outbound facing.
- `Checkpoint.hasTorchPlacement(key)` checks the saved ledger; `Checkpoint.recordTorchPlacement(key, pose, route, config)` commits a successful placement. Main segments and left/right shaft routes have separate keys.

## Invariants and assumptions

- Right is `(outboundFacing + 1) % 4`, independent of current facing.
- No dig or placement occurs unless every required checked turn succeeds. The helper restores the original facing after niche-clear or placement outcomes and reports restoration failures.
- Stair torch placement starts at the centre-bottom checkpoint after the full 3×4 passage is cleared. It faces the computed right heading and places into the adjacent, already-cleared right column inside the passage. This path performs no niche dig and no added lateral move; checked turns restore the exact checkpoint pose. If placement or facing restoration fails, descent stops and the approach is unwound when possible. Automatic restart from an in-slice stair action remains unsupported by recovery classification.
- The caller suppresses stair torches when lighting is disabled and skips the landing slice. The ledger is capped at 4096 keys and records only successful placements. Power loss after placement but before ledger commit remains ambiguous and pending-action recovery prevents automatic continuation. At each persisted work-unit boundary, the coordinator checks stock against `supplies.minimumTorchesToDepart`; below that quota, it completes the current bounded unit and invokes normal checkpointed service, which unloads, refuels/restocks at base, and returns to the saved pose/cursor. If the left chest cannot restore the minimum, service stops at base with `NO_TORCHES`.
- The dig callback must be bounded and return a structured result. The caller owns selected-slot preservation and placement verification.

## Dependencies and current limitations

Uses `src.navigation.turn`, structured safety outcomes, and `src.persistence.checkpoint` for duplicate suppression; low-stock recovery uses `src.inventory.service` and `src.inventory.resupply`. Interrupted service can resume only from a known committed pose with a supported exact mining cursor. The active placement path verifies the turtle API's literal `place()` success but has not been tested in a Minecraft world. The legacy reference script has no torch-placement pattern to adapt.

## Verification

`tests/lighting_right_wall.lua` covers all route headings with unrelated current facings, all placement headings and starting facings, invalid frames, failed turns, niche clears, and live coordinate drift. `tests/persistence_state.lua` verifies torch keys survive reload and distinct route distances remain eligible. `tests/navigation_stair_slice.lua` verifies the optional callback runs at the centre after passage clearing and that failure unwinds to the prior committed centre before downward progress. `tests/stair_route.lua` verifies interval cadence and landing-slice exclusion. `tests/inventory_service.lua` verifies forced low-stock service uses the same checkpointed route, resupply, and exact return path. `tests/active_baseline_wiring.lua` configures four floors explicitly so its bounded shaft placement assertions are deterministic. No in-world lighting check was performed.
