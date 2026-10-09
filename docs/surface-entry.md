# Surface entry navigation

## Purpose

Move the single turtle from the canonical surface origin to the stairs mouth over the fixed four-block V1 entry, and reverse that known-clear route exactly.

## Implemented behavior

`SurfaceEntry.enter` performs exactly four checked level-forward moves while preserving height and facing. `SurfaceEntry.returnToOrigin` accepts only the calculated mouth pose for the recorded origin, then performs exactly four checked back moves without turning or digging. Both operations stop on the first failed or malformed movement result and return the last committed pose.

## Public entry points

- `require("src.navigation.surface_entry")`
- `SurfaceEntry.LENGTH` is the fixed V1 length `4`.
- `SurfaceEntry.mouthPose(origin)` calculates the expected stairs-mouth pose.
- `SurfaceEntry.enter({ pose, move })` executes the outward route.
- `SurfaceEntry.returnToOrigin({ pose, origin, move })` executes the exact reverse.

The supplied `move(movement)` callback must be the checked navigation boundary and return `pose, outcome`. Runtime callers remain responsible for fuel policy and durable movement intent/commit.

## Invariants and assumptions

- The origin is the canonical surface pose and its facing defines the stairs direction.
- Entry and return preserve `y` and `facing`.
- Entry contains exactly four forward actions; return contains exactly four back actions.
- Return starts only at the calculated mouth pose and uses no excavation or alternate route.
- A failed action never advances the module's committed pose or triggers another move.

## Dependencies

The module uses the shared pose and result contracts. Its deterministic test routes movement through `src/navigation/motion.lua`, the known-route graph, and the existing fake turtle for all four facings.

## Current limitations

This is a deliberately isolated navigation building block. The active coordinator does not invoke it yet. It does not carve a wider surface passage, descend stairs, create landings, or persist route phase progress. Those behaviors remain separate backlog items. No in-world verification has been performed.
