# Navigation pose

## Purpose

Track the single turtle's local `{x, y, z, facing}` pose without mutating the caller's current pose during calculations.

## Implemented behavior

`Pose.afterMove(pose, movement, succeeded)` returns a new pose. It applies a movement delta only when `succeeded` is exactly `true`; false, nil, and other values return an unchanged copy with `MOVE_FAILED`. The focused pose test compares forward/backward deltas at each of the four facings and verifies up/down deltas at each facing against the deterministic fake turtle. `src.navigation.motion` is the single raw move/turn authority: it invokes injected turtle API functions, commits a new pose only on literal success, and records successful movement edges in the supplied known route. It returns the updated pose and a typed outcome; callers install/persist that pose only after success.

`Pose.afterTurn(pose, direction, succeeded)` computes facing only when `succeeded` is literal `true`. It normalizes left and right turns into facing 0..3, including the westward wrap from left-of-north; false, nil, and other values return an unchanged pose with `TURN_FAILED`. The active coordinator journals turn intent through `src.persistence.state` before calling the turtle API and durably commits the changed facing only after literal success.

`src.navigation.action_stack` records bounded local route actions with explicit inverses. Unwind applies records in strict last-in-first-out order and removes a record only after its inverse callback returns literal `true`. A failed inverse therefore remains at the top of the stack so the caller cannot claim that physical recovery completed.

## Public entry points

`Turn.face(pose, targetFacing, applyTurn)` chooses the shortest sequence (zero, one, or two turns), asks the supplied checked callback to execute each turn, and validates the returned facing after every successful action. It stops at the first failed or inconsistent turn and returns the latest committed pose with a typed outcome. The coordinator callback uses its existing pending-action and pose-commit boundary, so successful turns remain recorded individually. Inventory service checks the result and stops before moving when facing fails.

- `require("src.navigation.pose")` (subject to the project loader's module path).
- `Pose.new(x, y, z, facing)` validates and creates a pose.
- `Pose.afterMove(pose, movement, succeeded)` computes a movement result.
- `Pose.afterTurn(pose, direction, succeeded)` computes a turn result.
- `require("src.navigation.motion").move(pose, route, movement, turtleApi)` executes one raw forward/back/up/down action, updates known route on success, and returns `(updatedPose, result)`.
- `Motion.moveWithPolicy(pose, route, movement, turtleApi, policy)` applies route/fuel admission before its supplied durable-intent hook and physical move.
- `require("src.navigation.motion").turn(pose, direction, turtleApi)` executes one left/right turn and returns `(updatedPose, result)`.
- `require("src.navigation.turn").face(pose, targetFacing, applyTurn)` sequences the fewest checked turns; the callback returns `(updatedPose, result)` for each turn.
- `require("src.navigation.action_stack").inverse(action)` maps `forward/back`, `up/down`, and `turnLeft/turnRight` pairs.
- `ActionStack.new()`, `.record(stack, action)`, and `.unwind(stack, applyInverse)` create, append, and safely reverse a bounded local action route.

## Invariants and assumptions

- Facing is `0=north/-z`, `1=east/+x`, `2=south/+z`, `3=west/-x`.
- Pose inputs are not mutated; only the motion boundary commits successful in-memory movement and turn results.
- Movement success is expected to be the boolean `true` returned by CC:Tweaked.
- Movement route edges and pose are committed only after the CC:Tweaked API returns literal `true`; failures use `MOVE_FAILED` and preserve both.
- Turn normalization always returns facing 0..3, including negative left-turn intermediate values; facing is committed only after the CC:Tweaked API returns literal `true`. Failures use `TURN_FAILED` and preserve facing. Persisted intent without a completed commit makes rebooted pose uncertain.
- Facing changes are performed one checked turn at a time. A failed turn stops the sequence immediately; the returned pose reflects any earlier committed turn.
- Action-stack records describe successful physical actions only. Unwind is strict LIFO, requires literal callback success, and retains the failed record plus all earlier records when an inverse cannot be completed.
- The route policy owns fuel/known-route admission. The coordinator supplies fuel callbacks and the durable-intent hook, and persists successful pose after motion; retry/mining decisions remain outside this module.

## Verification

`tests/navigation_pose.lua` covers pure pose transforms, all forward/back/up/down deltas across the four facings, failed movement preservation, turn outcomes, and left/right wrapping from every facing. `tests/navigation_face.lua` checks shortest turn sequences for every facing pair, checked failure stopping, and pose recording. `tests/navigation_action_stack.lua` checks every inverse pair, strict LIFO order, invalid-action rejection, and preservation of the failed recovery record. `tests/navigation_motion.lua` checks raw movement and turn success/failure, pose preservation, and route edge recording against `tests/fake_turtle.lua`. `tests/inventory_service.lua` verifies a failed facing change prevents further movement. The fake turtle changes only its in-memory pose; it does not call turtle APIs or move anything in a world.

## Dependencies and limitations

The pose transformations and action stack remain pure Lua. The coordinator owns durable intent/commit ordering through the persistence module. The policy-aware motion entry point knows only the route-policy input contract and intent callback; it does not know persistence formats, retries, or mining. `Turn.face` and `ActionStack.unwind` depend on caller-supplied checked callbacks and do not perform persistence themselves. The action stack is a foundational boundary for the future stair-slice implementation; existing vein traversal retains its domain-specific facing breadcrumbs until that persistence shape is migrated deliberately. Manual in-world integration testing remains outstanding.
