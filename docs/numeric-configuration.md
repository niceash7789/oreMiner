# Validated configuration

## Purpose

Load one versioned V1 job configuration, reject invalid or incomplete settings before the turtle acts, and provide an immutable normalized copy to the coordinator.

## Implemented behavior

Root `config.lua` returns the complete schema-version-1 table from `MINER_PLAN.md`. `src.config.loader.normalize(config)` first applies the existing numeric/fixed-geometry rules, then requires every V1 section and validates booleans, item-ID lists, quota maps, ore mode and Lua patterns, retry/time limits, feature flags, and the canonical route/chest sides. It deep-copies the input and adds the compatibility fields consumed by the current coordinator; it never mutates the loaded table.

The coordinator loads and normalizes this file before constructing a run, shows a read-only summary, and asks only for start confirmation. Branch dimensions, paving, and ore behavior are no longer changed interactively. Invalid configuration raises `CONFIG_INVALID` before persistence setup, movement, digging, refuelling, or inventory actions.

`src.config.numeric_validation.validate(config)` remains the pure migration-compatible lower-level validator. It continues accepting omitted nested fields for focused legacy callers, while the loader requires the complete file schema.

## Public entry points

- `require("config")` returns the operator-edited V1 configuration table.
- `require("src.config.loader").normalize(config)` returns `normalized, outcome`.
- `require("src.config.numeric_validation").validate(config)` remains available for lower-level numeric/fixed-geometry checks.

## Invariants and assumptions

- Validation and normalization are pure and perform no turtle, filesystem, or inventory operation.
- The complete loader requires schema version 1 and all documented V1 sections. Fixed stairs geometry, tunnel height, floor-main turn, chest sides, and lighting side must match the implemented values.
- The normalized table is a deep copy. Runtime compatibility aliases do not appear in or mutate `config.lua`.
- Configuration is loaded once for a run and is not changed after confirmation.
- Configuration validation is independent of movement, inventory, and persistence modules.

## Dependencies and limitations

The loader depends on the numeric validator and shared structured-result helper. It uses only CC:Tweaked-compatible Lua features and does not dynamically execute configuration text beyond normal `require` loading.

`tests/config_loader.lua` verifies the shipped file, copy/normalization behavior, required fields, lists, flags, patterns, and representative invalid values. `tests/config_startup.lua` proves the active coordinator rejects an invalid schema with zero turtle calls. `tests/numeric_validation.lua` retains exhaustive numeric boundary coverage, and `tests/active_baseline_wiring.lua` exercises a short run using file-backed values. Floor/stairs execution does not consume its new configuration fields until those later phases are wired. No in-world verification has been performed.
