# Fuel policy and item classification

## Purpose and behavior

Classify fuel and floor-paving items by exact, configurable item IDs and gate each proposed movement on the exact cost of a known reversible route home plus reserve. When the estimate requires more fuel, the miner tries permitted onboard fuel and verifies the tank again; it refuses the move if the threshold is still unmet. Unlimited fuel is accepted without numeric comparisons.

`src.fuel.known_route` stores each successful movement as an undirected cleared edge. `src.fuel.route_policy` computes the shortest known return path from the projected pose, adds the reserve, and applies the verified refuel policy before each move. Every successful move is recorded after the pose transform succeeds, so active branch or vein excursion depth contributes to return cost as it is traversed. An unknown current route fails closed.

## Public entry points

- `require("src.config.defaults")` returns defaults under `fuel.allowedItems` and `paving` (`enabled=false`, `retainedCount=64`, and exact `allowedItems`).
- `require("src.config.item_policy").isFuel(itemId, config)`, `.isPaving(itemId, config)`, `.retainedCount(itemId, config)`, `.isProtected(itemId, config)`, and `.mayConsumeForPaving(itemId, config, availableCount)` provide exact-ID classification and the paving stock gate.
- `require("src.fuel.policy").canMove(level, requiredFuel, refuel, readFuel)` returns `(allowed, reason)` and confirms fuel after an attempted refuel.
- `require("src.fuel.route_policy").canMove(options)` accepts pose, known route, proposed movement, reserve, and fuel callbacks, returning `(allowed, reason, requiredFuel, proposedPose)`.
- `require("src.fuel.known_route").new(homePose)` creates a route graph; `.projectedReturnCost(route, currentPose, proposedPose)` returns the exact known cost or a failure reason; `.recordMove(route, fromPose, toPose)` adds a confirmed unit edge.
- `src.navigation.motion.moveWithPolicy(pose, route, movement, turtleApi, policy)` invokes route admission, then the `beforeMove` durable-intent hook, then checked physical motion and route/pose commit. The coordinator persists the returned pose after success.

## Invariants and assumptions

- Namespaced item IDs are compared exactly; display names and substring matching are not used.
- Fuel selection remains bounded to 16 inventory slots and uses only configured allowed fuel IDs.
- Route policy does not update pose or route edges; the motion layer commits both only after successful physical movement.
- Movement intent is persisted after fuel admission and before the physical API call; the coordinator persists committed pose after success.
- A movement is allowed only when the current tank meets the projected known-route cost plus `fuel_reserve`, or fuel is unlimited.
- Route edges connect adjacent block positions and represent successful, reversible movement through cleared cells. Cost is the shortest path through recorded edges, including the proposed edge.
- Defaults preserve coal, charcoal, and coal blocks as fuel. Paving item IDs remain cobblestone, cobbled deepslate, dirt, and netherrack, but paving is disabled by default and cobblestone's effective retained quota is zero while disabled.
- With paving enabled, at least one item beyond the retained cobblestone stock must exist before placement is allowed. Fuel, torches, configured ores, configured protected IDs, and unclassified IDs cannot be consumed for paving.

## Dependencies and limitations

The fuel policy uses standard Lua functions and callbacks. The known-route graph depends on successful movement reports from the coordinator; refuelling uses the existing slot guard and item policy. Full configured inventory quota accounting and item-wise service unloading remain separate backlog work.

The route graph is in-memory and is not a persisted route stack. It assumes previously traversed edges remain passable; external world changes can invalidate reversibility, which requires later return-route recovery work. It does not reconcile route state after reboot. Exact cost is therefore guaranteed for the active run's recorded known graph only; unknown/disconnected routes fail closed. Iterative vein unwind and checked return movement remain separate unchecked items.

Focused verification: route/fuel, motion, persistence, return, and active wiring checks are listed in `docs/STATUS.md`.
