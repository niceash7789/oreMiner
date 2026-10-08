# Implementation status

- Last completed checklist item: `MVP / P0 — Implement and unit-test pose transforms for all facings` in `MINER_PLAN.md`. Existing pure pose transforms cover all four facings; the focused verification now passes.
- Plan decisions resolved: the V1 default branch length is 30, matching the preserved reference and active baseline; mandatory main-shaft backfill owns a configurable 64-item cobblestone reserve whether paving is enabled or disabled. Optional paving and branch-end ejection may consume only stock above that reserve.
- Prioritization: dependency-ready P0 safety/correctness precedes P1 capability and P2 quality. Numerical configuration validation is next, followed by fixed-geometry config validation and surface-entry/stairs work.
- Next eligible unchecked item: `MVP / P0 — Reject non-integers, non-positive floor/step/branch counts and lengths, spacing below 2, thresholds outside 1..15, and negative reserves/quotas` in the configuration rules of `MINER_PLAN.md`.
- Files changed for the pose-transform item: existing `src/navigation/pose.lua`, `tests/navigation_pose.lua`, `docs/navigation-pose.md`, `MINER_PLAN.md`, and this handoff note. `reference/branch_miner_phase1.lua` remains unchanged.
- Verification passed with the configured Lua runtime: `tests/navigation_pose.lua` and `luac.exe -p src/navigation/pose.lua tests/navigation_pose.lua`. No in-world verification was performed.
- Blockers: none for the next item. The active runtime has no branch-end ejection path, so that separate routing behavior remains unchecked; any future implementation must use the same reserve quota.
- Current limitations: the action stack is a foundational boundary for the future stair-slice route; existing vein traversal still uses its domain-specific facing breadcrumbs. The active coordinator has no staircase, floor, or torch-placement phases. Full hierarchical service routing and `status`/`resume` commands remain unimplemented.
- Scope: `miner.lua` executes the active `src/branch_miner.lua` copy. V1 remains single-turtle; no networking, controller, or fleet code was added.
