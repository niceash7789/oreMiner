# Navigation pose

## Purpose

Track the single turtle's local `{x, y, z, facing}` pose without mutating the caller's current pose during calculations.

## Implemented behavior

`Pose.afterMove(pose, movement, succeeded)` returns a new pose. It applies a movement delta only when `succeeded` is exactly `true`; false, nil, and other values return an unchanged copy with `MOVE_FAILED`. `src.navigation.motion` is the single raw move/turn authority: it invokes injected turtle API functions, commits a new pose only on literal success, and records successful movement edges in the supplied known route. It returns the updated pose and a typed outcome; callers install/persist that pose only after success.

`Pose.afterTurn(pose, direction, succeeded)` computes facing only when `succeeded` is literal `true`. False, nil, and other values return an unchanged pose with `TURN_FAILED`. The active coordinator journals turn intent through `src.persistence.state` before calling the turtle API and durably commits the changed facing only after literal success.

## Public entry points

- `require("src.navigation.pose")` (subject to the project loader's module path).
- `Pose.new(x, y, z, facing)` validates and creates a pose.
- `Pose.afterMove(pose, movement, succeeded)` computes a movement result.
- `Pose.afterTurn(pose, direction, succeeded)` computes a turn result.
- `require("src.navigation.motion").move(pose, route, movement, turtleApi)` executes one raw forward/back/up/down action, updates known route on success, and returns `(updatedPose, result)`.
- `Motion.moveWithPolicy(pose, route, movement, turtleApi, policy)` applies route/fuel admission before its supplied durable-intent hook and physical move.
- `require("src.navigation.motion").turn(pose, direction, turtleApi)` executes one left/right turn and returns `(updatedPose, result)`.

## Invariants and assumptions

- Facing is `0=north/-z`, `1=east/+x`, `2=south/+z`, `3=west/-x`.
- Pose inputs are not mutated; only the motion boundary commits successful in-memory movement and turn results.
- Movement success is expected to be the boolean `true` returned by CC:Tweaked.
- Movement route edges and pose are committed only after the CC:Tweaked API returns literal `true`; failures use `MOVE_FAILED` and preserve both.
- A turn's facing is committed only after the CC:Tweaked API returns literal `true`; failures use `TURN_FAILED` and preserve facing. Persisted intent without a completed commit makes rebooted pose uncertain.
- The route policy owns fuel/known-route admission. The coordinator supplies fuel callbacks and the durable-intent hook, and persists successful pose after motion; retry/mining decisions remain outside this module.

## Verification

`tests/navigation_pose.lua` covers pure pose transforms. `tests/navigation_motion.lua` checks raw movement and turn success/failure, pose preservation, and route edge recording against `tests/fake_turtle.lua`. The fake turtle changes only its in-memory pose; it does not call turtle APIs or move anything in a world.

## Dependencies and limitations

The pose transformations remain pure Lua. The coordinator owns durable intent/commit ordering through the persistence module. The policy-aware motion entry point knows only the route-policy input contract and intent callback; it does not know persistence formats, retries, or mining. Manual in-world integration testing remains outstanding.
