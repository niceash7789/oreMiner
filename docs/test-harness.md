# Deterministic turtle test harness

## Purpose and implemented behavior

Provide a small pure-Lua turtle double for navigation and coordinator tests. `tests/fake_turtle.lua` tracks local pose, accepts queued outcomes for each movement and turn, leaves pose unchanged on failure, and records calls for assertions.

## Public API

- `FakeTurtle.new(pose, outcomes?)` creates the double.
- `move(direction, explicitResult?)` and `turn(direction, explicitResult?)` apply only literal `true` outcomes.
- `setOutcomes(action, outcomes)` replaces an action's deterministic result queue.
- `callCount(action)` returns the number of recorded invocations.

## Invariants and assumptions

The helper models pose and action outcomes only; inventory, world inspection, fuel, and persistence remain purpose-built fakes in their focused tests. Inputs use the project's `0..3` facing convention.

## Dependencies and limitations

Pure Lua with no runtime dependency. It is test-only and is not loaded by the miner.

## Verification

`tests/fake_turtle_behavior.lua`, the navigation tests, and `tests/branch_progress.lua` exercise the helper.
