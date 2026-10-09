# Fuel and return movement

## Purpose

Keep ordinary return travel on edges the turtle has already traversed and keep fuel checks tied to the known route home.

## Implemented behavior

`KnownRoute.hasEdge(route, fromPose, toPose)` confirms that a proposed return step is an existing recorded edge. `ReturnMove.run(options)` rejects unknown edges without moving, retries movement on a known edge within the supplied bound, and returns `RETURN_BLOCKED` after persistent failure. The coordinator's `safeForward()` uses this helper; return movement no longer invokes `digForward()` as a shortcut fallback. Successful physical moves continue to update pose and route only through the checked movement commit path.

`RouteHome.run(options)` performs a bounded breadth-first search over the recorded edge graph, then follows only those checked edges to the saved home coordinate and optionally restores the original facing. The active baseline invokes it after all mining units complete, before printing success or marking the snapshot complete. Search is limited to 100,000 discovered route nodes by default; unknown or oversized routes stop without movement. This is a safe graph return for the active baseline while the planned stairs/floor hierarchy is being integrated.

The startup estimate no longer prints “continue anyway.” If permitted onboard fuel cannot satisfy that estimate, the run stops with `NO_FUEL` before mining movement. Every later move remains independently gated by the exact known-route cost plus reserve.

## Public entry points

- `require("src.fuel.known_route").hasEdge(route, fromPose, toPose)`
- `require("src.navigation.return_move").run(options)` with `hasEdge`, `move`, integer `maxAttempts`, and optional bounded `recover(attempt)` callback.
- `require("src.navigation.route_home").path(route, pose, maxNodes)` returns the coordinate sequence to home using known edges only.
- `require("src.navigation.route_home").run(options)` requires checked `move` and `turn` callbacks and returns the final known pose plus a structured result.

## Invariants and assumptions

- Route edges are recorded bidirectionally only after successful adjacent movement, so each edge represents a cell previously entered/cleared by this turtle.
- The caller supplies the planned adjacent pose and the movement callback remains responsible for fuel policy and pose commit.
- Turn results and persistence of the graph are outside this item.

## Dependencies and limitations

The helpers depend only on callback contracts. `src/branch_miner.lua` supplies the in-memory `KnownRoute`, checked movement/turn commits, and the existing finite dig-retry count as the retry bound; retries wait briefly but do not dig. The graph return is not yet a replacement for the plan's domain-aware branch/junction/landing/stairs hierarchy, and service-triggered return/resume is still incomplete. Manually obstructed edges stop with an error for operator recovery.

## Verification

`tests/return_move.lua` verifies a recorded edge is traversed without digging, an unknown edge is rejected before movement, and a persistent blockage stops at the configured attempt limit. `tests/route_home.lua` covers graph return, home-facing restoration, unknown-origin rejection, and movement failure. `tests/active_baseline_wiring.lua` verifies a completed live-coordinator run ends at the exact origin pose.
