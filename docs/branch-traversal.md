# Two-level branch traversal

## Purpose

Describe the bounded lower-outbound and upper-return route through one straight floor branch.

## Implemented behavior

`BranchTraversal.new(branch, length)` creates a pure route geometry object. `outboundPose(distance)` returns poses from the lower junction through the branch endpoint at the floor's lower level. The active coordinator mines outward on that lower lane, rises one block, then always returns through the cleared upper lane, including when ore scanning is disabled. When scanning is enabled, it scans the exposed sides and ceiling at each upper cell. Upper-lane movement uses the checked fuel-aware movement wrapper to record new clear edges; it never digs during return. The turtle descends at the junction and restores the main-facing heading. The coordinator verifies exact endpoint and junction poses. Cursor records are persisted before each outbound, turnaround, upper-return, and junction-descent unit. Committed outbound, turnaround, upper-return, and junction-descent cursors resume at their exact phase and cell only after recovery validates the matching landing-derived pose and known route home. The dispatcher continues the same side, completing the left shaft before the right when applicable.

## Public entry points

- `require("src.navigation.branch_traversal")`
- `require("src.mining.branch_progress")`
- `BranchTraversal.new(branch, length)` returns a traversal and structured status.
- `traversal.outboundPose(distance)` accepts an integer from `0` through `length`.
- `traversal.upperReturnPose(returnDistance)` accepts an integer from `0` through `length`, measured from endpoint toward junction.
- `traversal.canonicalJunctionPose()` returns the lower junction pose and status.
- `BranchProgress.run(length, step, firstIndex)` returns `BRANCH_LENGTH_REACHED` only after all requested steps succeed; `firstIndex` supports resuming a lower outbound at its next unmined cell. An early movement stop returns `BRANCH_SHORTENED` with completed/requested counts. Typed callback failures are propagated.
- `require("src.mining.branch_resume").start(cursor, branchCount, spacing, branchLength)` validates a supported outbound or return-phase branch cursor and maps its phase, pair, side, committed distance, and next action.

## Invariants and assumptions

- `y=0` and `y=1` are relative to the active floor; the supplied branch origin remains the recorded lower floor coordinate.
- Mining clears the two-high tunnel on every outbound cell, providing the upper lane for endpoint rise and return.
- The return heading is opposite the outbound heading. A checked final turn restores the canonical main-facing direction from `FloorGrid.branch`.
- Calls return fresh pose values; they do not mutate the branch or traversal geometry.
- This module computes route poses only. A caller commits pose changes only after confirmed turtle actions and applies the pending-action/persistence and fuel-route rules.

## Dependencies and limitations

`src/navigation/branch_traversal.lua` depends on the branch record from `src/navigation/floor_grid.lua` and no turtle API. `src/mining/branch_progress.lua` is a small coordinator helper and accepts a step callback. The active inline executor fails closed before return if outbound movement cannot reach configured length. Short branches and pose mismatches are fatal errors, not recorded skips; it does not attempt alternate recovery from an incomplete branch. A lower-lane return cursor is not emitted and remains unsupported. Each upper return edge is first traversed through the outbound-cleared two-high passage and is committed only after literal turtle success. Configured tunnel cadence places torches on the route-defined right wall during the lower outbound pass. In-world dimensions and external world changes remain hardware checks.

## Verification

Run `lua tests/navigation_branch_traversal.lua`, `lua tests/branch_progress.lua`, `lua tests/branch_resume.lua`, and `lua tests/persistence_recovery.lua` from the repository root. In addition to route geometry and bounded movement failure, persistence recovery reloads lower-outbound and upper-return checkpoints for both sides, verifies phase/next-action and exact pose/facing against the recorded landing geometry, and rejects changed poses.
