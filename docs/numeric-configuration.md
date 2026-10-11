# Validated configuration

## Purpose

Load one versioned V1 job configuration, reject invalid or incomplete settings before the turtle acts, and provide an immutable normalized copy to the coordinator.

## Implemented behavior

The tracked example sets `mining.stairStepsPerFloor = 4`, `mining.firstFloorDepthOffset = 0`, and `lighting.stairInterval = 2`. Set the offset to the number of extra descending slices before floor 1. Validation accepts integer intervals from 4 through 64 and offsets from 0 through 60, provided their sum does not exceed 64. Omitting the offset in an older V1 config means zero. `mining.stairHeight = 4` remains fixed. The example sets `mining.branchPairs = 2` for a short test run: two left and two right branches per floor. This differs from the plan's 20-pair production example; the validated pair count is configurable. Existing installed `config.lua` files are retained by the installer and must be checked separately.

Tracked `config.example.lua` returns the complete schema-version-1 table from `MINER_PLAN.md`. The installer copies it to the untracked live `config.lua` only when that file is absent, so a pull can update the example without overwriting operator settings. At runtime, `src.config.source.load` selects `config.lua` when present and otherwise reads `config.example.lua` directly from the miner's installation directory. A present but broken live file stops startup; it never falls back. `src.config.loader.normalize(config)` first applies the existing numeric/fixed-geometry rules, then requires every V1 section and validates booleans, item-ID lists, quota maps, ore mode and Lua patterns, retry/time limits, feature flags, and the canonical route/chest sides. It rejects top-level `workers`, `workerCount`, `turtleCount`, and `fleet` fields so unsupported multi-turtle settings cannot be silently accepted. The coordinator uses one local sequential executor and one persisted mining cursor. It deep-copies the input and adds the compatibility fields consumed by the current coordinator; it never mutates the loaded table.

The coordinator loads and normalizes the selected file before constructing a run, shows its path in the read-only summary, and asks only for start confirmation. Branch dimensions, paving, and ore behavior are no longer changed interactively. Missing or invalid configuration raises `CONFIG_INVALID` before persistence setup, movement, digging, refuelling, or inventory actions.

`src.config.numeric_validation.validate(config)` remains the pure migration-compatible lower-level validator. It continues accepting omitted nested fields for focused legacy callers, while the loader requires the complete file schema.

## Public entry points

- Installed `config.lua` returns the operator-edited V1 configuration table; `config.example.lua` is the tracked template and runtime fallback.
- `require("src.config.source").load(fs, shell, require, dofile)` returns the selected raw table, file path, and optional load error.
- `require("src.config.loader").normalize(config)` returns `normalized, outcome`.
- `require("src.config.numeric_validation").validate(config)` remains available for lower-level numeric/fixed-geometry checks.

## Invariants and assumptions

- Validation and normalization are pure and perform no turtle, filesystem, or inventory operation.
- The complete loader requires schema version 1 and all documented V1 sections. Stair interval is an integer from 4 through 64; the optional first-floor offset is an integer from 0 through 60, and the combined first descent is at most 64. Stair width/height, surface entry, tunnel height, floor-main turn, chest sides, and lighting side must match the implemented values.
- The normalized table is a deep copy. Runtime compatibility aliases do not appear in or mutate `config.lua`.
- Configuration is loaded once for a run and is not changed after confirmation. Only absence of `config.lua` permits the example fallback.
- Configuration validation is independent of movement, inventory, and persistence modules.
- V1 has one turtle and one active sequential work cursor; multi-worker configuration is invalid.

## Dependencies and limitations

The loader depends on the numeric validator and shared structured-result helper. The source selector uses CC:Tweaked filesystem, shell, and `dofile` APIs; it executes only the selected Lua configuration file. An isolated test harness without those CC APIs can supply an injected `config` module.

`tests/config_source.lua` checks live-file priority, missing-file fallback, and refusal to bypass a broken live file. `tests/config_loader.lua` verifies copy/normalization behavior, required fields, lists, flags, patterns, representative invalid values, and rejection of worker/fleet settings using an independent test-only fixture. The tests do not assert values from the editable `config.example.lua`. `tests/config_startup.lua` proves the active coordinator rejects an invalid schema with zero turtle calls. `tests/numeric_validation.lua` retains exhaustive numeric boundary coverage, and `tests/active_baseline_wiring.lua` exercises a short run using the test-only fixture. No in-world verification has been performed.
