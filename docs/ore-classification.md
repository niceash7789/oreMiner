# Ore classification

## Purpose

Classify inspected blocks for ore seed discovery and bounded vein traversal without relying only on an `_ore` suffix.

## Implemented behavior

`OreClassifier.isOre(block, config)` consumes the block record returned by `turtle.inspect*`, including `name` and optional `tags`. Ignore names and tags take precedence in every mode. The modes behave as follows:

- `all`: accept a configured name, configured ore tag, or configured Lua name pattern, except ignored names/tags.
- `whitelist`: accept only configured names or tags, except ignored names/tags; name patterns are not consulted.
- `blacklist`: accept every positively classified ore (configured names, tags, or patterns) except ignored names/tags.
- `valuable`: accept only names in the user-maintained `valuableNames` list; no broad modpack database is included.

Missing or malformed block data and missing config fail closed. Invalid Lua patterns are ignored safely. Defaults use `c:ores`, `forge:ores`, and `_ore$` as a fallback, with empty explicit and ignore lists.

In `all` and `blacklist` modes, positive recognition comes only from configured tags, names, or patterns. “All” does not mean mining every adjacent block. An adjacent block that does not match a positive ore rule is left alone.

The active coordinator applies the same classifier to forward, up, down, and adjacent inspected blocks. Each adjacent block is accepted into a vein based on its own classifier result, so connected qualifying resources may use different block IDs. For the traversal boundary, inspected block records and an explicit `qualifies(block)` predicate are passed separately; the traversal does not load classifier or configuration modules.

## Public entry points

- `require("src.mining.ore_classifier")`
- `OreClassifier.isOre(block, config)` returns a boolean.
- `src.config.defaults.ore` supplies the default policy; the coordinator passes `config.ore` to each classification call.
- `VeinTraversal.run(checkpoint, ops, seedInverse, qualifies)` receives the policy predicate explicitly; its `ops.inspect(direction)` returns `found, blockData`.

## Invariants and assumptions

- Only positive configured evidence classifies a block; no broad namespace guesses are made.
- The inspected `name` must be a non-empty string. Tags follow CC:Tweaked's keyed tag map, with array form also accepted for deterministic callers/tests.
- Ignore rules always override include rules.
- Pattern strings use Lua pattern syntax, matching `string.find` behavior.

## Dependencies and limitations

The classifier has no turtle or external dependencies. Users configure ore policy in root `config.lua`; the validated normalized copy is supplied to the active coordinator. `OreClassifier.missingConfiguredTags(config)` returns a deterministic warning list only when `config.availableTagKeys` supplies an authoritative registry; without one it returns no speculative warnings. Vein traversal remains bounded by its block and distance caps and returns `VEIN_INVALID_QUALIFIER` if no predicate is supplied.

## Verification

Run `C:/Users/Game/AppData/Local/Programs/Lua/bin/lua.exe tests/ore_classifier.lua` and the focused vein/fuel tests listed in `docs/STATUS.md`.
## Tag availability warning

The active API provides tags only for a specific block returned by `turtle.inspect*`; it does not expose the current modpack's complete registry. The implementation never infers absence from sampled blocks. Pack authors may provide `ore.availableTagKeys` to enable warning-only validation before movement.
