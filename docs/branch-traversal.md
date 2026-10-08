# Two-level branch traversal

## Purpose

Describe the bounded lower-outbound and upper-return route through one straight floor branch.

## Implemented behavior

`BranchTraversal.new(branch, length)` creates a pure route geometry object. `outboundPose(distance)` returns poses from the lower junction through the branch endpoint at the floor's `y=0` level. After reaching the endpoint, the turtle rises one block through the already-cleared two-high tunnel. `upperReturnPose(returnDistance)` returns poses in reverse order at `y=1`, from endpoint to upper junction, where the caller can scan the upper exposed surfaces. `canonicalJunctionPose()` identifies the lower junction pose after descending at the junction and restoring the main-tunnel facing. The active coordinator uses `BranchProgress.run` to require every configured outbound step before starting return traversal.

## Public entry points

- `require("src.navigation.branch_traversal")`
- `require("src.mining.branch_progress")`
- `BranchTraversal.new(branch, length)` returns a traversal and structured status.
- `traversal.outboundPose(distance)` accepts an integer from `0` through `length`.
- `traversal.upperReturnPose(returnDistance)` accepts an integer from `0` through `length`, measured from endpoint toward junction.
- `traversal.canonicalJunctionPose()` returns the lower junction pose and status.
- `BranchProgress.run(length, step)` returns `BRANCH_LENGTH_REACHED` only after all steps succeed; an early movement stop returns `BRANCH_SHORTENED` with completed/requested counts. Typed callback failures are propagated.

## Invariants and assumptions

- `y=0` and `y=1` are relative to the active floor; the supplied branch origin remains the recorded lower floor coordinate.
- The branch's two-high tunnel provides the cleared upper lane for both the endpoint rise and the upper return.
- The return heading is opposite the outbound heading. The canonical junction facing is supplied by `FloorGrid.branch`.
- Calls return fresh pose values; they do not mutate the branch or traversal geometry.
- This module computes route poses only. A caller commits pose changes only after confirmed turtle actions and applies the pending-action/persistence and fuel-route rules.

## Dependencies and limitations

`src/navigation/branch_traversal.lua` depends on the branch record from `src/navigation/floor_grid.lua` and no turtle API. `src/mining/branch_progress.lua` is a small coordinator helper and accepts a step callback. The active inline branch executor uses it to fail closed before upper scan/return if outbound movement cannot reach configured length. Short branches are fatal errors, not recorded skips; this code does not attempt a recovery/return from the incomplete branch.

## Verification

Run `lua tests/navigation_branch_traversal.lua` and `lua tests/branch_progress.lua` from the repository root. The tests cover route geometry, exact step completion, and a bounded fake-turtle blocked-movement failure.
