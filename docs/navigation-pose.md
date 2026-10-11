# Navigation pose

## Purpose

Track the single turtle's local `{x, y, z, facing}` pose without mutating the caller's current pose during calculations.

## Implemented behavior

`Pose.afterMove(pose, movement, succeeded)` returns a new pose. It applies a movement delta only when `succeeded` is exactly `true`; false, nil, and other values return an unchanged copy with `MOVE_FAILED`. The focused pose test compares forward/backward deltas at each of the four facings and verifies up/down deltas at each facing against the deterministic fake turtle. `src.navigation.motion` is the single raw move/turn authority: it invokes injected turtle API functions, commits a new pose only on literal success, and records successful movement edges and the current home breadcrumb in the supplied known route. It returns the updated pose and a canonical `src.safety.result` outcome that satisfies the shared result contract; callers install/persist that pose only after success. Coordinates are absolute within the mine's frame, whose fixed surface origin is `(0,0,0)`.

`Pose.afterTurn(pose, direction, succeeded)` computes facing only when `succeeded` is literal `true`. It normalizes left and right turns into facing 0..3, including the westward wrap from left-of-north; false, nil, and other values return an unchanged pose with `TURN_FAILED`. The active coordinator journals turn intent through `src.persistence.state` before calling the turtle API and durably commits the changed facing only after literal success.

For ordinary movement and turning, `src/branch_miner.lua` calls `Checkpoint.beginAction` before the physical API and `Checkpoint.commitAction` immediately after installing a successful new pose (and route edge for movement). During stair traversal it instead uses `Checkpoint.beginRouteAction` and `Checkpoint.commitRouteAction` to persist the inverse edge with pending intent, then commit the new pose and remove the edge atomically. A literal turtle API failure cancels intent while retaining the prior pose; a failed post-success commit leaves the on-disk pending intent as the safe reboot signal.

`src.navigation.action_stack` records bounded local route actions with explicit inverses. Unwind applies records in strict last-in-first-out order and removes a record only after its inverse callback returns literal `true` or a typed result with `ok=true`. `unwindPersisted` saves the shortened stack after every inverse before attempting the next one. If that save fails, it restores the record in memory and stops; the physical pose may then be ambiguous, so callers must fail closed. A failed inverse also remains at the top of the stack.

The stack validator rejects sparse, malformed, non-reversible, or over-limit records. Persistence sessions can durably append a reversible action before subsequent work and retire only the matching top inverse after the caller has committed that physical inverse. This is a storage primitive; active mining and resume do not yet drive it end-to-end.

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
- `ActionStack.validate(stack)` checks dense reversible records and the maximum depth.
- `ActionStack.unwindPersisted(stack, applyInverse, persist)` commits each completed inverse through a caller-supplied durable writer.
- `Session.unwindRouteStack(applyInverse, pose, route, configSnapshot)` applies the stack through the checkpoint session and persists each inverse boundary.

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

`tests/navigation_pose.lua` covers pure pose transforms, all forward/back/up/down deltas across the four facings, failed movement preservation, turn outcomes, and left/right wrapping from every facing. `tests/navigation_face.lua` checks shortest turn sequences for every facing pair, checked failure stopping, and pose recording. `tests/navigation_action_stack.lua` checks every inverse pair, strict LIFO order, invalid-action rejection, failed inverse retention, structured checked success, per-inverse persistence ordering, and persistence-failure stopping. `tests/navigation_motion.lua` checks raw movement and turn success/failure, pose preservation, and route edge recording against `tests/fake_turtle.lua`. `tests/inventory_service.lua` verifies a failed facing change prevents further movement. The fake turtle changes only its in-memory pose; it does not call turtle APIs or move anything in a world.

For the assigned pose-transform checklist item, `C:/Users/Game/AppData/Local/Programs/Lua/bin/lua.exe tests/navigation_pose.lua` passed, as did `luac.exe -p src/navigation/pose.lua tests/navigation_pose.lua`. The plan item is checked. No in-world verification was performed.

## Dependencies and limitations

The pose transformations and action stack remain pure Lua. The coordinator owns durable intent/commit ordering through the persistence module. The policy-aware motion entry point knows only the route-policy input contract and intent callback; it does not know persistence formats, retries, or mining. `Turn.face` and `ActionStack.unwindPersisted` depend on caller-supplied checked callbacks. The active branch and vein traversals still use their own in-memory reversible progress; end-to-end persisted stack wiring and automatic resume remain incomplete. Manual in-world integration testing remains outstanding.
