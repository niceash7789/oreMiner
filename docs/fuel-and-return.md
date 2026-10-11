# Fuel and return movement

## Purpose

Keep ordinary return travel on edges the turtle has already traversed and keep fuel checks tied to the known route home.

## Implemented behavior

`KnownRoute.hasEdge(route, fromPose, toPose)` confirms that a proposed return step is an existing recorded edge. `ReturnMove.run(options)` rejects unknown edges without moving, retries movement on a known edge within the supplied bound, and returns `RETURN_BLOCKED` after persistent failure. The coordinator's `safeForward()` uses this helper; return movement no longer invokes `digForward()` as a shortcut fallback. Successful physical moves continue to update pose and route only through the checked movement commit path.

`RouteHome.run(options)` follows the saved per-move home breadcrumb when it matches the current pose and the destination is home. The breadcrumb removes loops when a move revisits an earlier recorded cell. Other destinations and older snapshots without a breadcrumb use a bounded breadth-first search over the recorded edge graph. Every return step checks the recorded edge and committed pose. Search and breadcrumb length are limited to 100,000 nodes; unknown or oversized routes stop without movement.

Before any route movement, the coordinator verifies the turtle can retain the configured reserve (or refuels from permitted onboard fuel); otherwise it persists `NO_FUEL` and stops at the origin. Startup and base service budget the specific departure and replay routes. Every move, including recorded-route service travel, is independently gated by exact known-route return cost plus reserve. Floor mining does not refuel toward a whole-job estimate, which could consume the onboard coal supply before the route requires it.

`Motion.moveWithPolicy` fails closed with `NO_FUEL` when a numeric tank cannot meet the projected route commitment after permitted refuelling, or when the fuel reading is unavailable. The commitment includes one unit for the proposed move, the resulting breadcrumb path home, and reserve. It returns before action intent is written or the turtle movement API is called. A higher-level caller may select a service or return path only after independently proving that the recorded route home is affordable.

`FuelLevel.isUnlimited` and `FuelLevel.format` keep CC:Tweaked's string fuel sentinel out of numeric comparisons and display it consistently in startup, service, route, status, and completion output. `Motion.move` samples fuel around the physical move and reports only an observed numeric decrease as `fuelUsed`; the coordinator adds that delta after confirmed movement. Refuelling increases and unlimited readings do not inflate consumption statistics.

`KnownRoute.costHome(state)` computes the saved breadcrumb length from the committed pose to the origin; older snapshots use the exact shortest recorded graph route. For an active or unwinding vein, it validates every saved inverse breadcrumb against the recorded route and requires the breadcrumb walk to end at its tunnel checkpoint, then measures from the committed pose so the excursion retrace is counted once. Unsupported or incomplete route evidence returns an error instead of an estimate. `Motion.moveWithPolicy` remains the final admission gate before each runtime movement, including proposed outward edges.

`costHome` also refuses snapshots whose pose certainty is not `known` or that contain a pending physical action, returning `POSITION_UNCERTAIN` before producing a numeric cost. This prevents downstream status/fuel decisions from treating an ambiguous move or turn as an actionable route. `tests/route_home_mining_phases.lua` builds recorded route graphs to lower main-shaft, left/right lower branch, and left/right upper-scan checkpoints, returns each to exact origin/facing, and injects a first-edge return failure.

Before vein traversal digs a newly discovered ore candidate, `RoutePolicy.canExplore` applies that same known-route-plus-reserve commitment to the projected candidate pose. It may consume configured onboard fuel through the checked refuel callback and verifies the resulting tank level. Unknown routes or insufficient fuel deny discovery, causing the vein to unwind; the movement wrapper repeats admission before entering the candidate.

## Public entry points

- `require("src.fuel.refuel").toTarget(api, target, config)` consumes only verified configured fuel, restores the selected slot, and requires both a falling stack count and rising tank level after each successful `refuel(1)`. It stops after at most 1,024 consumed items and returns `(ok, code)`. The coordinator uses it for route admission and automatic reserve refuelling.

- `require("src.fuel.known_route").hasEdge(route, fromPose, toPose)` and `.trailHome(route, pose)`
- `require("src.fuel.known_route").costHome(state)` returns `(moves, "KNOWN_ROUTE_COST")` or `(nil, reason)`.
- `require("src.fuel.route_policy").canExplore(options)` for pre-dig vein admission.
- `require("src.fuel.level")` provides `isUnlimited(level)`, `format(level)`, and `consumed(before, after)` for safe sentinel handling and observed consumption.
- `require("src.navigation.motion").moveWithPolicy(pose, route, movement, turtleApi, policy)` for checked fuel admission and typed denial.
- `require("src.navigation.return_move").run(options)` with `hasEdge`, `move`, integer `maxAttempts`, and optional bounded `recover(attempt)` callback.
- `require("src.navigation.route_home").path(route, pose, maxNodes)` returns the coordinate sequence to home using known edges only.
- `require("src.navigation.route_home").run(options)` requires checked `move` and `turn` callbacks and returns the final known pose plus a structured result.

## Invariants and assumptions

- Route edges are recorded bidirectionally only after successful adjacent movement, so each edge represents a cell previously entered/cleared by this turtle.
- The caller supplies the planned adjacent pose and the movement callback remains responsible for fuel policy and pose commit.
- Phase/cursor estimates never replace the known cleared-route graph; active vein depth is priced from the committed pose only after each inverse breadcrumb matches a recorded edge to its checkpoint.
- Turn results and persistence of the graph are outside this item.

## Dependencies and limitations

The helpers depend only on callback contracts. `src/branch_miner.lua` supplies the in-memory `KnownRoute`, checked movement/turn commits, and the existing finite dig-retry count as the retry bound; retries wait briefly but do not dig. Inventory service uses the graph to travel to home and back to its saved work pose. The graph return is not a replacement for the domain-aware branch/junction/landing/stairs hierarchy. Manually obstructed edges stop with an error for operator recovery. The active coordinator maintains durable pre-service checkpoints and provides validated `status` and `resume` commands; physical reboot behavior remains an operator check.

## Verification

`tests/fuel_level.lua` covers unlimited formatting, numeric and non-numeric readings, observed fuel decreases, and no consumption on increases. `tests/return_move.lua` verifies a recorded edge is traversed without digging, an unknown edge is rejected before movement, and a persistent blockage stops at the configured attempt limit. `tests/known_route_fuel.lua` covers phase-independent exact home cost, uncertainty/pending-action refusal, verified vein breadcrumb depth, rejected incomplete breadcrumbs, pre-dig admission with exact refuel, failed refuel, and unlimited fuel. `tests/navigation_motion.lua` verifies fuel denial emits no intent or movement call, reports actual movement fuel delta, and maps numeric shortfall and unavailable fuel to `NO_FUEL`. `tests/route_home.lua` covers graph return, home-facing restoration, unknown-origin rejection, and movement failure. `tests/route_home_mining_phases.lua` covers lower main-shaft and lower/upper left/right branch offsets, exact origin-facing restoration, recorded-edge-only movement, and immediate stop on injected return failure. These focused tests and syntax checks passed on 2026-10-09.


Resume fuel uses src/fuel/resume_commitment.lua. 	argetFuelForTrips(homeMoves, resumeMoves, reserve, workStepMoves) accounts separately for the route home and the replay route from origin; floor replay includes each saved entry, stair centreline pair, and landing move plus any recorded route from the landing to the checkpoint. The coordinator validates these route counts before refuelling or moving. 	ests/resume_commitment.lua covers the arithmetic and invalid inputs.
