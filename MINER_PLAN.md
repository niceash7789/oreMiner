# CC:Tweaked Surface-to-Depth Single-Turtle Miner Plan

Status: planning only; no miner implementation is included in this document.

This plan uses the supplied single-file branch miner as the baseline. The workspace contained no existing source files, so the review below is of the supplied script rather than a checked-in implementation.

## 1. Decisions at a glance

The recommended V1 is a deliberately constrained multi-floor shaft miner:

- The turtle starts on the surface at `(0,0,0)`, facing the mine, with a supply chest on its left and a primary ore/output chest on its right.
- An optional bulk-output chest sits behind the turtle for cobblestone, gravel, and other configured bulk material. When it is not configured, the turtle ejects excess `minecraft:cobblestone` into the dead end at each shaft turnaround instead of carrying routine cobblestone home.
- It moves forward four level centreline blocks before the first descending stair step.
- It mines three-block-wide, three-block-tall diagonal stairs. Each completed slice advances the centreline one block forward and one block down.
- After eight downward steps it carves a flat 3×3 landing with three blocks of clear headroom. Each later floor is another eight blocks lower.
- The stairs enter the rear-centre of the landing, the canonical landing pose is its centre block, and the floor's main shaft starts from that centre by turning right.
- At every landing it mines a complete one-block-wide, two-block-high shaft-mining floor.
- When a floor is complete, it returns to that floor's landing centre, restores the stairs-facing orientation, and descends to the next floor from the front-centre edge.
- Paired left and right shafts at each junction.
- Shaft junctions three blocks apart, measured centreline-to-centreline.
- Shaft length 30 and 20 shaft pairs by default. This preserves the proven single-turtle baseline while configuration validation is added.
- Floor count is configurable; four floors is the proposed bounded default.
- Floor paving is off by default.
- Torch placement is enabled, supplied from the left chest, and always uses the route-defined right-hand wall.
- Inventory service begins at 14 occupied slots, after stack consolidation.
- Fuel is governed by an invariant, not a warning: the turtle may not make a move that would leave it unable to retrace a known route home plus its reserve.
- Veins use an iterative depth-first search with a visited set, a reversible route stack, a distance cap, and a block cap. Lua recursion is not used.
- A vein is always unwound to its shaft checkpoint before an unload trip. The turtle never plots a direct route home from an arbitrary vein cell.
- After mining ore exposed by a main shaft, V1 seals every resulting opening in the main-shaft wall, floor, or ceiling flush with `minecraft:cobblestone`; deeper hidden vein cells do not need to be solid-filled.
- V1 unloads ores to the right chest, optionally separates bulk blocks into the rear chest, ejects excess cobblestone at shaft ends when there is no rear chest, and refuels/restocks torches from the left chest before resuming.
- V1 writes local checkpoints and resumes only when pose is known. If a reboot happens while a physical movement or turn is marked pending, it stops with `POSITION_UNCERTAIN`; GPS-free software cannot safely infer whether that action completed.
- No GPS, networking, controller, fleet logic, GUI, general pathfinding, or aggressive liquid handling is included in V1.

### Canonical terminology

Use this route hierarchy in product requirements, operator messages, and new public APIs:

1. **Stairs** — the 3-wide × 3-tall surface descent/ascent route. This replaces “staircase” and the old “shaft work” label.
2. **Floor** — one mining level reached from a stairs landing.
3. **Main shaft** — the straight level route that starts at the centre of a floor's 3×3 landing and turns right from the stairs direction. This replaces “floor main tunnel.”
4. **Shaft** — either paired left/right mining route perpendicular to the main shaft. This replaces “branch” or “branch tunnel.”

The preserved filenames `reference/branch_miner_phase1.lua` and `src/branch_miner.lua` retain their historical names. Existing code identifiers that still use `staircase`, `mainTunnel`, or `branch` are migration targets; do not treat those legacy names as new product terminology.

## 2. Classification scheme

Every backlog item carries one of these tiers:

- **MVP** — required before the miner can be called reliably unattended under the documented V1 constraints.
- **NEXT** — high-value follow-up which depends on the MVP foundation but is not required for the first safe release.
- **LATER** — useful expansion which should not shape V1 beyond clean interfaces.
- **EXPERIMENTAL** — uncertain, modpack-dependent, or potentially fragile; prototype behind a disabled feature flag.

Priority within a tier is expressed as P0 (safety/correctness), P1 (core capability), P2 (quality/efficiency), or P3 (optional).

### AI implementation model index

Every checkbox ends with one recommended coding-model index:

| Index | Recommended model | Use for this project |
|---|---|---|
| **AI-1** | `gpt-6-luna` · low | Cheapest default for mechanical edits, documentation, reporting, mocks, simple helpers, and routine tests. |
| **AI-2** | `gpt-6-luna` · medium | Default for most feature implementation, including stateful modules, when the task has a tight scope, explicit contracts, and tests. |
| **AI-3** | `gpt-6.1-sol` · medium | Limited to the highest-risk architecture/recovery decisions, milestone integration review, or a verified defect Luna cannot resolve reliably. |

The index is deliberately aggressive about Codex allowance use: 388 of the 397 feature checkboxes use Luna, only 9 use Sol, and none normally use Astra. Start with AI-1 for mechanical work, use AI-2 for bounded feature work, and use AI-3 only for the specially marked items or a milestone-level review of combined safety-critical changes. If Luna fails an objective test, retry once with a smaller prompt and clearer evidence before escalating. Mechanical follow-up work should drop back to AI-1. Model names and availability reflect the plan revision on 8 October 2026 and should be checked before implementation. The selection follows [official OpenAI model-selection guidance](https://developers.openai.com/api/docs/guides/model-selection), the [GPT-6 Luna model page](https://developers.openai.com/api/docs/models/gpt-6-luna), and the [Codex allowance and credit schedule](https://learn.chatgpt.com/docs/pricing).

Allowance note: use GPT-6 Luna rather than GPT-5.6 Luna. At Standard speed, the published Codex credit rates are 2.5 input / 0.25 cached-input / 12.5 output credits per million tokens for GPT-6 Luna, versus 5 / 0.5 / 30 for GPT-5.6 Luna. GPT-5.6 therefore does not conserve allowance. Included subscription usage is variable, so the Codex usage dashboard remains the source of truth for the account's actual remaining limits and reset times.

Cost-control workflow:

1. Give one checkbox or one tightly coupled module to the model at a time; include only the relevant contracts and tests.
2. Use AI-1 for planning-to-code translation, fixtures, mocks, documentation, and straightforward test cases.
3. Use AI-2 for the normal implementation pass and require it to run the relevant deterministic tests.
4. Use AI-3 once at each milestone boundary to review the combined diff, safety invariants, and failure tests rather than paying for Sol on every feature.
5. Astra is an emergency manual escalation only, not a planned coding model. Use it only after a concrete test failure remains unresolved by Sol.

## 3. Baseline script assessment

### Retain as concepts

- [x] **MVP / P0** Retain the local pose model `{x, y, z, facing}` and the convention `0=north/-z`, `1=east/+x`, `2=south/+z`, `3=west/-x`. — **AI-2**
- [x] **MVP / P0** Retain the rule that pose changes only after a turtle movement succeeds. — **AI-2**
- [x] **MVP / P1** Retain paired left/right branches and the fixed origin/facing contract, but place each branch grid at a recorded staircase landing. — **AI-1**
- [x] **MVP / P1** Retain the efficient two-level branch traversal: mine outbound at `y=0`, then return at `y=1` to scan the upper exposed surfaces. — **AI-1**
- [x] **MVP / P1** Retain the idea of preserving the selected inventory slot around helper operations. — **AI-1**
- [x] **MVP / P1** Retain item-ID-based fuel and paving classification, but move the lists into configuration. — **AI-1**
- [x] **MVP / P1** Retain small-terminal status messages and basic counters. — **AI-1**
- [x] **MVP / P0** Retain bounded entity/block retry as an idea, with typed outcomes and consistent limits. — **AI-2**

### Fix before reuse

- [x] **MVP / P0** Replace `inventoryFull()` with threshold-based inventory pressure. Waiting for all 16 slots violates the required two-slot headroom. — **AI-2**
- [x] **MVP / P0** Check inventory inside vein traversal before every new dig, not only before and after a complete vein. — **AI-2**
- [x] **MVP / P0** Make low fuel a control decision. The current `checkFuel()` prints a critical warning and still returns `true`, so the turtle can knowingly strand itself. — **AI-2**
- [x] **MVP / P0** Replace Manhattan-distance-only fuel estimates with exact known-route costs. Manhattan distance can underestimate a retrace through a vein. — **AI-2**
- [x] **MVP / P0** Replace recursive vein mining with an explicit stack and an inverse-movement breadcrumb stack. — **AI-2**
- [x] **MVP / P0** Check every return movement. Return helpers now propagate fallback failures, branch upper-scan ascent/step/descent failures stop the branch, and vein inverse breadcrumbs fail closed. — **AI-2**
- [x] **MVP / P0** Bound falling-block digging by attempts and elapsed time. The current `while detect()` loops can run indefinitely. — **AI-2**
- [x] **MVP / P0** Treat an unexpectedly shortened branch as an error or an explicitly recorded skip. The current branch code can hit a blocker, shorten `actualLength`, and still report success. — **AI-2**
- [x] **MVP / P0** Do not dig a new shortcut during ordinary return travel. A return route should use already-cleared cells; unexpected blockage should trigger bounded recovery and then stop. — **AI-2**
- [x] **MVP / P0** Validate turn results before changing facing, even though normal turtle turns usually succeed. The active turn adapter commits facing only after a literal `true` API result and returns `TURN_FAILED` otherwise. — **AI-2**
- [x] **MVP / P1** Replace `_ore$` as the entire ore classifier. It misses many modded resources and cannot use the tags returned by `inspect`. The configurable classifier uses inspected tags, explicit IDs, fallback name patterns, and ignore rules. — **AI-1**
- [x] **MVP / P1** Permit a connected vein to contain multiple qualifying ore block IDs instead of requiring every block to have the first ore's exact name. — **AI-1**
- [x] **MVP / P1** Scan the main shaft as well as the paired shafts. The supplied script only vein-scanned the routes historically called branches. Main-shaft cells now inspect both walls, floor, and ceiling through the configured classifier and bounded vein traversal. — **AI-1**
- [x] **MVP / P1** After each ore vein entered from the main shaft unwinds, seal every resulting opening in the main-shaft wall, floor, or ceiling flush with `minecraft:cobblestone` before main-shaft travel resumes. Do not solid-fill hidden vein cavities or place blocks in the 1×2 passage. Verify every placement and restore the exact checkpoint pose/facing. The coordinator seals only the exposed checkpoint face after exact vein unwind, verifies `place` and inspected cobblestone, and stops on failure. — **AI-2**
- [x] **MVP / P1** Make paving default to `false`. While disabled, give cobblestone no paving-only quota; while enabled, allow paving to consume only stock above the separate mandatory main-shaft backfill reserve and never fuel, torches, ores, unknown items, or other protected inventory. Defaults and the active CLI disable paving unless explicitly enabled. The mandatory backfill reserve remains a separate unchecked requirement. — **AI-1**
- [x] **MVP / P1** Protect a configurable `minecraft:cobblestone` working reserve for mandatory main-shaft backfill even when paving is disabled; paving and shaft-end ejection may consume only cobblestone above that reserve. `inventory.retainedItems["minecraft:cobblestone"]` is the shared reserve/quota, defaults to 64, and is enforced by paving eligibility and aggregate chest unloading regardless of paving state. No runtime shaft-end ejection path exists yet. — **AI-1**
- [x] **MVP / P1** Validate numerical input ranges; reject nonpositive, fractional, and impractically large values before confirmation. Active and nested settings bound branch length to `1..256`, branch pairs to `1..100`, and spacing to `2..64`; deterministic numeric validation passes. — **AI-1**
- [x] **MVP / P1** Replace chest-name substring detection with a configurable accepted-block policy and, most importantly, verify the result of every drop. Exact configured block IDs gate chest acceptance; each drop must return literal success and leave the source slot empty. — **AI-1**
- [x] **MVP / P1** Preserve configured quantities, not a privileged slot. Aggregate configured item-ID quotas are allocated across stacks in slot order, and excess drops are verified. — **AI-1**
- [x] **MVP / P1** Separate safety errors from normal `false` results. For example, “nothing to dig” and “unbreakable block” must not share an ambiguous boolean. The active dig outcome is `NO_BLOCK` for an empty cell and typed fatal codes for dig/movement/scan/inventory safety failures; caller propagation is covered by deterministic tests. — **AI-1**
- [x] **MVP / P1** Persist progress. All supplied state currently exists only in memory. The active coordinator now writes schema-checked local snapshots with a valid backup, saves intent before movement/turn and commits pose after literal success, and refuses corrupt, incompatible, pending, or incomplete state rather than restarting it. Full domain-specific resume remains separate unchecked work. — **AI-1**

### Separate into modules

- [x] **MVP / P1** Separate raw turtle motion/pose tracking from mining-policy decisions. Raw move/turn calls and successful in-memory pose/route commits now go through `src/navigation/motion.lua`; fuel admission and pending-intent/durable-state ordering remain in the coordinator. — **AI-1**
- [x] **MVP / P1** Separate route costing and fuel policy from the movement primitive itself. `src.fuel.route_policy` owns shortest-known-route projection, reserve addition, and verified fuel admission; the policy-aware motion entry point runs it before the durable-intent callback and physical action. — **AI-1**
- [x] **MVP / P1** Separate inventory accounting/unloading from pattern execution. The inventory service now owns pressure decisions, verified chest unloading, retained-quantity policy application, and return/resume coordination; pattern code invokes its pressure and service checkpoints. — **AI-1**
- [x] **MVP / P1** Separate ore classification from vein traversal. `src.mining.ore_classifier` owns configurable policy; vein traversal receives inspected block data and an explicit qualification predicate, with no classifier/config dependency. — **AI-1**
- [x] **MVP / P1** Separate durable state encoding/checkpointing from the live state machine. `src/persistence.checkpoint` now owns durable run creation/loading, live-state snapshot copying, action intent/commit/cancel, and fatal/completion writes; the coordinator passes its live pose and route through that boundary. — **AI-1**
- [x] **MVP / P2** Keep logging and statistics behind tiny interfaces so failures in optional reporting cannot stop mining. `src.reporting.safe` guards terminal writes and `src.reporting.statistics` owns protected observational counter updates/reads; a fake-turtle run verifies a failing terminal sink does not interrupt mining. — **AI-1**

### Replace outright

- [ ] **MVP / P0** Replace the assumption that `(0,0,0)` is already on a mining floor with the four-block surface entry, 3-wide × 3-tall stairs, recorded flat 3×3 landings, and a main shaft that begins at each landing's centre block. — **AI-2**
- [ ] **MVP / P0** Replace the single rear-chest service assumption with the required left supply/right primary-output layout and optional rear bulk routing. — **AI-2**
- [ ] **MVP / P0** Replace direct coordinate-axis return from arbitrary positions with hierarchical route unwinding: vein to checkpoint, shaft to junction, main shaft to the landing centre, recorded stairs to surface origin. — **AI-2**
- [ ] **MVP / P0** Replace recursive call-stack backtracking with an explicit, persisted route stack. — **AI-2**
- [ ] **MVP / P0** Replace “continue anyway” fuel behaviour with `RETURN_REQUIRED` or `NO_FUEL`. — **AI-2**
- [ ] **MVP / P0** Replace ad-hoc booleans with structured results such as `{ok, code, message, retryable}`. — **AI-2**
- [ ] **MVP / P1** Replace interactive configuration as the normal launch path with a validated config file; keep a minimal confirmation/summary only when appropriate. — **AI-1**

## 4. Recommended mining strategy

### Overall pattern

The turtle begins on the surface. The initial facing defines the stairs direction. It first travels four level centreline blocks so the stair mouth is clear of the chests. It then mines eight three-by-three diagonal stair slices to the rear-centre edge of the first floor landing. It carves a flat 3×3 landing with three blocks of clear headroom, advances one level block to the landing centre, completes that floor's shaft grid, returns to the same centre, crosses the front-centre landing cell, and begins the next eight-slice descent. This repeats until `floorCount` floors are complete.

One stair slice is a deterministic excavation sweep:

1. From the current centre-bottom checkpoint, clear and move forward into the middle of the target slice.
2. Clear the centre block above and below.
3. Sweep into the left column, clear its upper and lower blocks, and return to centre.
4. Sweep into the right column, clear its upper and lower blocks, optionally carve/place a torch in a niche beyond the outer right wall, and return to centre. Skip torch placement on a landing slice so the right-turn floor entrance remains clear.
5. Restore the stairs facing and move down into the target slice's centre-bottom checkpoint.

The lateral sweep creates a 3-wide × 3-tall cross-section while restoring the turtle to the centreline. Each slice advances one block forward and one block down. A landing adds a 3-wide × 3-long flat platform: the completed eighth slice is the rear-centre cell, the saved landing pose is one level block forward at the centre cell, and the front-centre cell is one more level block forward. With the four-block surface entry and default interval, the landing centres are 13 blocks forward/8 blocks down for floor 1 and 23 blocks forward/16 blocks down for floor 2. In general, floor `n` has depth `-n * stairStepsPerFloor` and centreline forward offset `surfaceEntryLength + n * (stairStepsPerFloor + 2) - 1`. The inverse slice climb is up, then back; landing crossings are recorded level moves. Every movement is persisted separately.

“Right-hand side” is defined by the planned outbound direction of that route, not whichever way the turtle happens to face while returning. Stair torches go on the outer right wall relative to the descent direction. Main-shaft and shaft torches go on the right wall relative to their outbound mining direction. Return and service travel never places torches.

At each landing centre, the floor's main shaft turns right relative to the stairs direction. With the documented facing convention, northbound stairs produce an eastbound main shaft. Paired shafts therefore run north/south and do not occupy the stairs centreline.

```text
Side view of stairs (centreline)

Surface/base  T____
                   \_
                     \_
                       r-c-f  -> floor 1 landing; main shaft exits right from c
                         \_
                           \_
                                 r-c-f  -> floor 2 landing

The level surface entry is 4 blocks long.
Each carved stair slice is 3 wide × 3 tall and advances forward/down by 1.
Each landing floor is exactly 8 blocks below the previous landing.
r/c/f are the rear-centre, canonical centre, and front-centre cells of a flat 3×3 landing.
```

The lifecycle for each floor is:

1. On the first descent, travel `surfaceEntryLength` level blocks from base to the stair mouth.
2. Descend `stairStepsPerFloor` recorded 3×3 stair slices to the landing's rear-centre cell, carve the flat 3×3 landing, and move level to its centre.
3. Save and assert the centre landing pose, face right, and begin that floor's main shaft from that same centre block.
4. At each junction, mine one complete shaft and return before starting the other.
5. Complete every configured shaft pair on that floor.
6. Use the final main-shaft trip back to scan the upper level, sealing main-shaft ore openings flush with cobblestone after each vein unwind.
7. Return to the exact landing centre at `y=0` relative to the floor, face the stairs direction, and commit `floorComplete`.
8. Cross the front-centre landing cell and descend the next stair segment, or climb the recorded stairs and reverse the four-block surface entry if the job is complete.

Paired left/right shafts remain preferable to alternating a single side because every completed pair ends at an unambiguous canonical pose on that floor's main-shaft centreline.

The work sequence for each shaft pair within a floor is:

1. Advance the main shaft by `shaftSpacing` blocks at the lower level.
2. Scan the lower main-shaft walls and floor as each cell is completed.
3. Mine and scan the left shaft; return to its junction.
4. Mine and scan the right shaft; return to its junction.
5. Commit `shaftPairComplete` and continue.

Do not mine opportunistically during inventory/fuel service travel on the stairs or a completed floor. Service travel should follow known-clear cells and be as predictable as possible.

### Tunnel geometry

Recommended defaults:

| Setting | Default | Rationale |
|---|---:|---|
| Floor count | 4 | Bounded initial multi-floor job; configurable. |
| Vertical interval | 8 | Matches the requested first floor at depth 8 and provides clear separation between two-high floor tunnels. |
| Surface entry | 4 level blocks | Keeps the 3×3 stair mouth clear of the base chests. |
| Stair cross-section | 3 wide × 3 tall | Requested spacious access route, carved by a deterministic slice sweep. |
| Stair centreline | Net 1 forward + 1 down per slice | Deterministic and exactly reversible without pathfinding. |
| Floor main direction | Right from landing | Keeps the branch grid separate from the staircase column and makes every landing identical. |
| Main tunnel | 1 wide × 2 high | Minimum excavation with safe player/turtle access. |
| Branch tunnel | 1 wide × 2 high | Matches the baseline's efficient lower-outbound/upper-return scan. |
| Branch length | 30 | Preserves the proven reference baseline and bounds each recovery leg; configuration validation may accept other safe positive integers. |
| Branch pairs | 20 | A bounded initial job rather than an infinite miner. |
| Branch spacing | 3 | Junction centreline distance; leaves two solid block rows between parallel branches, each exposed from one side. |
| Both sides | `true` | Nearly doubles useful exposure per main-tunnel distance and keeps junctions canonical. |
| Paving | `false` | Avoids supply dependency and accidental placement until core navigation is proven. |
| Stair torch interval | 4 slices | Lights each eight-step segment while leaving landing slices clear. |
| Tunnel torch interval | 8 centreline blocks | Configurable cadence; every torch is in the planned outbound right-side niche. |

Spacing semantics must be documented precisely. With centreline spacing 3, adjacent branch tunnels have two intact block rows between them. Each row is exposed by one tunnel wall, so single-block deposits are not hidden between branches. Spacing 2 leaves only one shared row, causing duplicate exposure and more excavation per searched volume. Spacing 4 or more leaves at least one middle row not directly exposed, improving excavation efficiency but potentially missing isolated ore. Therefore 3 is the reliability-oriented default; 4 may be offered later as an efficiency option.

### V1 geometry constraints

- The surface entry is straight and level for exactly four blocks.
- The staircase is straight, 3 wide, and 3 tall. Each slice restores the turtle to the centre-bottom lane and advances that lane exactly one block forward and down; V1 does not build turns or switchbacks.
- The first landing is `surfaceEntryLength + stairStepsPerFloor` blocks forward and `stairStepsPerFloor` blocks below base. Later landings add one forward/down displacement per stair slice.
- Every floor main tunnel turns right from the staircase and is straight and level.
- Every branch is straight, level, and perpendicular to its floor's main tunnel.
- A floor is considered complete only after every configured branch pair and the final upper main scan have returned to the landing.
- Only one active branch excursion exists at a time.
- The turtle does not route around bedrock, liquids, protected blocks, or player construction.
- Bounded 3×3 slice sweeps and vein motion are the only non-centreline excursions, and every successful movement records its inverse.
- Home remains the surface pose `(0,0,0)`, between the required left/right chests; the optional bulk chest is behind the turtle's initial facing.

These constraints are features: they make safe return possible without generic pathfinding or GPS.

## 5. Proposed configuration model

Use one `config.lua` file returning a table. Validate and normalise it at startup, then store a snapshot of job-affecting values in run state. Avoid mutating config while a job is in progress.

```lua
return {
  schemaVersion = 1,

  mining = {
    floorCount = 4,
    surfaceEntryLength = 4,
    stairStepsPerFloor = 8,
    stairWidth = 3,
    stairHeight = 3,
    floorMainTurn = "right",
    branchLength = 30,
    branchPairs = 20,
    branchSpacing = 3,
    tunnelHeight = 2,
    scanMainTunnel = true,
  },

  inventory = {
    returnThreshold = 14,
    autoConsolidate = true,
    autoUnload = true,
    keep = {
      ["minecraft:coal"] = 64,
      ["minecraft:torch"] = 64,
      ["minecraft:cobblestone"] = 64, -- mandatory main-shaft backfill reserve
    },
  },

  fuel = {
    autoRefuel = true,
    reserve = 100,
    allowedItems = {
      "minecraft:coal",
      "minecraft:charcoal",
      "minecraft:coal_block",
    },
  },

  ore = {
    enabled = true,
    mode = "all",
    names = {},
    tags = { "c:ores", "forge:ores" },
    namePatterns = { "_ore$" },
    ignoreNames = {},
    ignoreTags = {},
    maxBlocks = 64,
    maxRadius = 8,
  },

  base = {
    supply = "left",
    primaryOutput = "right",
    bulkOutput = "back",
    separateBulk = false,
    acceptedChestBlockIds = { "minecraft:chest", "minecraft:trapped_chest" },
  },

  supplies = {
    torchTarget = 64,
    minimumTorchesToDepart = 8,
    bulkNames = {
      "minecraft:cobblestone",
      "minecraft:cobbled_deepslate",
      "minecraft:gravel",
      "minecraft:dirt",
      "minecraft:netherrack",
    },
  },

  lighting = {
    enabled = true,
    itemNames = { "minecraft:torch" },
    stairInterval = 4,
    tunnelInterval = 8,
    skipLandingSlice = true,
    side = "right",
    wallHeight = 1,
  },

  safety = {
    moveRetries = 5,
    digRetries = 12,
    entityRetries = 5,
    retryDelay = 0.4,
    stopOnLiquid = true,
  },

  features = {
    paving = false,
    persistence = true,
    autoResupply = true,
    torches = true,
  },

  paving = {
    allowedItems = { "minecraft:cobblestone" },
    retainedTarget = 64, -- applied only while features.paving is true
  },
}
```

Configuration rules:

- [x] **MVP / P0** Reject non-integers, non-positive floor/step/branch counts and lengths, spacing below 2, thresholds outside `1..15`, and negative reserves/quotas. `src.config.numeric_validation.validate` checks active and nested-schema settings before run confirmation; deterministic numeric validation tests pass. — **AI-2**
- [x] **MVP / P0** Require `stairStepsPerFloor = 8` in V1. Keep it configurable in the schema for later validation/testing, but do not silently accept a geometry the implementation has not proved. `src.config.numeric_validation.validate` rejects any supplied value other than 8 before run confirmation; deterministic numeric validation tests pass. — **AI-2**
- [x] **MVP / P0** Require `surfaceEntryLength = 4`, `stairWidth = 3`, and `stairHeight = 3` in V1 rather than pretending the first implementation supports arbitrary stair geometry. `src.config.numeric_validation.validate` rejects any supplied value other than the fixed geometry before run confirmation; deterministic numeric validation tests pass. — **AI-2**
- [x] **MVP / P0** Require `floorMainTurn = "right"` in V1 so landing orientation and return routes stay canonical. `src.config.numeric_validation.validate` rejects any supplied unsupported value before run confirmation; deterministic numeric validation tests pass. — **AI-2**
- [x] **MVP / P0** Require supply left, primary output right, and optional bulk output behind relative to the initial surface facing. `src.config.numeric_validation.validate` rejects any supplied unsupported `base` side before run confirmation; omitted fields remain valid during config migration. Deterministic numeric validation tests pass. — **AI-2**
- [x] **MVP / P0** Require `lighting.side = "right"`; other sides are not supported until their route-frame semantics are tested. `src.config.numeric_validation.validate` rejects any other supplied side before run confirmation; deterministic numeric validation tests pass. — **AI-2**
- [x] **MVP / P0** Reject unsupported `tunnelHeight`; V1 supports exactly 2 rather than pretending the algorithm is generic. `src.config.numeric_validation.validate` rejects any supplied value other than 2 before run confirmation; deterministic numeric validation tests pass. — **AI-2**
- [x] **MVP / P1** Explain that `ore.mode="all"` means “all blocks positively classified as ore,” not “mine every adjacent block.” — **AI-1**
- [x] **MVP / P1** Define mode behaviour: — **AI-1**
  - `all`: any block matching an ore tag, configured name, or configured ore-name pattern, minus ignores.
  - `whitelist`: only explicit names/tags.
  - `blacklist`: all positively classified ores except explicit ignored names/tags.
  - `valuable`: a small user-maintained whitelist; do not ship a giant modpack database.
- [ ] **MVP / P1** Warn, but do not fail, when configured tag keys are absent in the current modpack. — **AI-1**
- [ ] **NEXT / P2** Support CLI overrides for a small stable subset such as length and pair count. — **AI-1**
- [ ] **LATER / P3** Support named job profiles. — **AI-1**

## 6. Proposed state model

Use `state.json` for the active snapshot and `state.bak` for the prior valid snapshot. JSON is inspectable and adequate for the simple string/number/boolean/table model. State must have a schema version and be validated on load.

Conceptual model:

```lua
state = {
  schemaVersion = 1,
  runId = "...",
  status = "mining", -- idle|mining|returning|servicing|resuming|complete|error
  poseCertainty = "known", -- known|uncertain

  pose = { x = 15, y = -8, z = -30, facing = 0 },

  progress = {
    workDomain = "floor", -- shaft|floor|ore|service
    workUnitId = "floor-1-branch-left-5",
    floor = 1,
    stairSegment = 1,
    stairStep = 8,
    branchPair = 5,
    side = "left", -- left|right|none
    phase = "branch_outbound_lower",
    offset = 18,
    mainOffset = 15,
    nextAction = "scan_left",
  },

  checkpoint = {
    pose = { x = 15, y = -8, z = -30, facing = 0 },
    progress = { ... },
  },

  landing = {
    pose = { x = 0, y = -8, z = -12, facing = 0 },
    floor = 1,
  },

  staircase = {
    direction = 0,
    surfaceEntryCompleted = 4,
    completedSteps = 8,
    landings = {
      { floor = 1, x = 0, y = -8, z = -12 },
    },
  },

  excursion = nil, -- or vein state below
  oreCandidates = {}, -- local queue; same turtle consumes it in V1
  service = nil,   -- or saved resume target and service stage

  pendingAction = nil, -- intent journal entry for a move/turn
  configSnapshot = { ... },
  stats = { ... },
  error = nil,
}
```

During vein traversal, `excursion` contains:

- `originPose`: exact tunnel checkpoint.
- `originProgress`: mining cursor to restore.
- `route`: ordered successful moves plus their inverse actions.
- `frontier`: iterative DFS work stack.
- `visited`: coordinate-key set for the current vein.
- `blocksMined`: count for the vein limit.
- `abortReason`: `nil`, `INVENTORY_RETURN`, `FUEL_RETURN`, or an error.

State invariants:

- `pose` is the last committed physical pose.
- `progress.floor`, `stairSegment`, and `stairStep` identify the active depth and whether the turtle is descending, mining a floor, or climbing.
- `progress.workDomain` and `workUnitId` identify the bounded local job. V1 has one executor and never assigns this work to another turtle.
- `progress.nextAction` describes what has not yet been completed; this avoids duplicating or skipping a stair step, floor, branch, or scan after resume.
- `landing.pose` is the canonical entry/exit pose for the active floor and never moves while that floor is active.
- `staircase.landings` and the recorded stair route must agree with the four-block entry and configured 3×3, one-forward/one-down slice geometry.
- `oreCandidates` found during a shaft sweep are consumed locally only after the slice reaches its canonical checkpoint.
- A non-empty `pendingAction` means a crash may have occurred between intent and commit. Automatic movement is prohibited until certainty is restored.
- A service trip never overwrites the saved mining checkpoint.
- `complete` is written only at origin after the final home/service action succeeds.

### Persistence checkpoints

- [x] **MVP / P0** Save an intent before every physical move and turn; commit the resulting pose immediately after success. The active coordinator persists pending intent before the turtle API and commits only after literal success; pending intent reports `POSITION_UNCERTAIN` after reboot. — **AI-2**
- [x] **MVP / P0** Save after changing the logical mining cursor, before beginning the next unit of work. `src/mining/cursor.lua` defines the validated next-action cursor for the active baseline, and the coordinator saves it through `Checkpoint.setProgress` before each main-shaft, junction, branch-outbound, turnaround, and return unit. Failed cursor persistence stops before the unit starts. — **AI-2**
- [ ] **MVP / P0** Save before entering a vein and after every successful vein move/frontier update. — **AI-2**
- [ ] **MVP / P0** Save before starting route unwind, before return home, on arrival home, before unload, after unload, and before resume departure. — **AI-2**
- [x] **MVP / P0** Save the fatal error before stopping. `markFatal` writes error status and code synchronously on a failed mining outcome; persistence test reloads and verifies the code. — **AI-2**
- [ ] **MVP / P1** Write to a temporary file, close it, validate it, rotate the current valid file to `.bak`, and move the temporary file into place. — **AI-2**
- [x] **MVP / P1** On load, validate schema, enum values, coordinate integers, route structure, and configuration compatibility. Version 1 snapshots now fail closed on invalid pose/config data, action/status enums, and malformed/non-reversible route graphs; expected configuration is validated before comparison. — **AI-1**
- [x] **MVP / P0** If both snapshots are invalid, stop with `STATE_CORRUPT`; never initialise a new run over an unrecognised active state. `State.load` returns `STATE_MISSING` only when active and backup files are both absent; otherwise it requires a valid active or backup snapshot. Startup aborts on `STATE_CORRUPT` before prompting or creating a run. Tests cover both-invalid and both-absent cases. — **AI-2**

Important limitation: local persistence cannot make movement perfectly atomic. If power is lost after the turtle physically moves but before the commit is saved, the file cannot determine whether the move happened. The intent record narrows the ambiguity to one action but does not resolve it. Without GPS, a landmark, or user confirmation, the safe result is `POSITION_UNCERTAIN`, not automatic movement.

## 7. Navigation design

### Single authority

Only `navigation.lua` may call:

- `turtle.forward`, `back`, `up`, `down`
- `turtle.turnLeft`, `turnRight`

Every wrapper must:

1. Validate that pose is known.
2. Ask the fuel policy whether the proposed move is allowed.
3. Persist pending intent when persistence is enabled.
4. Attempt the physical action.
5. Update pose only on success.
6. Commit state and clear pending intent.
7. Return a structured result.

Turns consume no fuel but still change durable orientation and therefore use the same intent/commit pattern.

### Route types

Use two distinct mechanisms rather than a general pathfinder:

- **Pattern routes:** derived from floor/branch progress and V1 geometry. Examples are branch cell to junction, floor main tunnel to landing, and landing through the staircase to the surface origin.
- **Excursion routes:** an explicit stack of successful vein moves with inverse actions. Unwind by popping the stack.

Home routing order is mandatory:

1. If in a temporary 3×3 slice sweep, unwind its local movement stack to the last committed centre-bottom staircase checkpoint.
2. If in a vein, unwind the exact excursion route to the saved tunnel checkpoint.
3. If in a branch, follow its cleared axis to its junction at the correct scan level, then normalise to `y=0` at the junction.
4. Follow the cleared floor main-tunnel axis to that floor's landing.
5. Face the staircase direction and climb the recorded centreline steps in reverse: up, then back, until the stair mouth.
6. Reverse the four-block level surface entry to `(0,0,0)`.
7. Restore the canonical surface-base facing before service.

Resume performs the recorded route in reverse hierarchy: surface origin down the known staircase to the active landing, landing along the floor main tunnel to the junction, junction to the saved branch offset and level, then restore facing and `nextAction`.

Navigation backlog:

- [x] **MVP / P0** Implement and unit-test pose transforms for all facings. `src/navigation/pose.lua` computes movement deltas for forward/back/up/down in every facing, with failure-safe turn transforms; `tests/navigation_pose.lua` verifies the transforms against the fake turtle. — **AI-2**
- [ ] **MVP / P0** Implement wrappers for six movements and two turns. — **AI-2**
- [ ] **MVP / P0** Prohibit direct turtle movement outside navigation. — **AI-2**
- [ ] **MVP / P0** Implement `face(targetFacing)` using the fewest checked turns. — **AI-2**
- [x] **MVP / P0** Implement reversible action records and inverse mapping. `src/navigation/action_stack.lua` records successful local actions, maps all supported inverses, and preserves the failed record when checked LIFO unwind stops. — **AI-2**
- [ ] **MVP / P0** Implement the four-block surface-entry route and its exact reverse. — **AI-2**
- [ ] **MVP / P0** Implement a checked 3×3 stair-slice sweep that restores centreline pose before moving down. — **AI-2**
- [ ] **MVP / P0** Implement the exact inverse centreline climb: move up, then back, with no new digging on a known-clear staircase. — **AI-2**
- [ ] **MVP / P0** Treat every lateral carving move as a reversible sub-action and assert centre-bottom pose/facing at the end of each slice. — **AI-2**
- [ ] **MVP / P0** Record and assert every floor landing pose. — **AI-2**
- [ ] **MVP / P0** Implement branch-to-junction, junction-to-landing, and landing-to-surface route builders. — **AI-2**
- [ ] **MVP / P0** Assert canonical pose at every phase boundary. — **AI-2**
- [ ] **MVP / P0** On an unexpected obstruction in a known-clear return cell, retry within limits and then stop; do not tunnel around it. — **AI-2**
- [ ] **NEXT / P2** Add an operator-assisted `home` command that is only enabled when pose is known. — **AI-1**
- [ ] **LATER / P3** Add constrained detours around obstacles only if a provable inverse route can be retained. — **AI-1**

## 8. Inventory and base-service design

### Inventory pressure

The primary threshold is occupied slots after consolidation, default 14. Two empty slots provide headroom for differently typed drops during unwind. The threshold is a return trigger, not proof that further digging is safe.

Check pressure:

- Before a tunnel dig.
- After collecting from a tunnel dig.
- Before entering a vein.
- Before every new vein dig.
- After every vein dig.
- Before leaving a checkpoint to resume work.

If the threshold is reached in a vein, set `abortReason=INVENTORY_RETURN`, stop discovering new nodes, unwind to the tunnel checkpoint, then begin the normal service route. If the inventory becomes completely full during unwind, continue only through already-clear cells. If an unexpected block requires digging, stop with `INVENTORY_CRITICAL` rather than risk losing valuable drops or drifting from the route.

### Consolidation

Consolidation is a best-effort pass over all slots. Attempt `transferTo` between compatible stacks, verify actual source/target counts, and do not assume matching names guarantee matching NBT or stack compatibility. Restore the selected slot afterward.

### Keep quotas, routing, and resupply

Keep rules are totals by item ID across all slots, not designated slot numbers. The default service targets are one coal stack as emergency onboard fuel, one torch stack, and a configurable 64-item `minecraft:cobblestone` working reserve for mandatory main-shaft backfill. That backfill reserve applies whether paving is enabled or disabled. Optional paving and branch-end ejection may consume only cobblestone above the reserve; paving does not create a second implicit quota.

### Branch-end cobblestone ejection

When no rear bulk chest is configured, eject excess `minecraft:cobblestone` at the physical dead end of every successfully completed branch. Perform this after the lower outbound pass reaches its configured endpoint and before ascending for the upper return pass, so the dropped items remain in the dead end and outside the return path. This is the only planned world-dropping behavior in V1.

Consolidate first, preserve the mandatory backfill reserve across arbitrary slots, then use checked `turtle.drop()` calls for cobblestone above that reserve. Verify that the selected-slot and total cobblestone counts decrease by the requested amount. Bound all attempts and stop with `EJECT_FAILED` if an excess stack cannot be ejected completely; do not claim the branch turnaround is complete. Never eject ores, unknown items, fuel, torches, or other configured bulk items. If a service return occurs before the branch endpoint, carry the inventory home normally rather than making an early dump in a travel cell.

When a rear bulk chest is configured and enabled, do not perform branch-end ejection. Preserve configured bulk items for verified unloading into that chest.

At base, process inventory in this order:

1. Consolidate compatible stacks.
2. Retain configured supply quotas.
3. If bulk separation is enabled, face back and unload only explicitly configured bulk item IDs into the rear chest. Branch-end cobblestone ejection is disabled in this mode.
4. Face right and unload every remaining non-supply item into the primary output chest. This conservative fallback keeps unknown modded valuables out of the bulk chest.
5. If bulk separation is disabled, send all inventory that reached base to the right chest. Routine excess cobblestone should already have been ejected only at completed branch endpoints; residual cobblestone from an interrupted branch or upper return is safe to route right at base.
6. Face left, return excess supply items if needed, refuel from allowed items, and restock torches up to their quota.
7. Verify internal fuel and minimum torch count before resuming.
8. Restore the canonical forward facing.

For each drop, verify post-drop counts; a successful partial transfer is not a complete unload. Safety may consume coal below the keep quota. “Keep 64” is a service target, not a prohibition against using emergency fuel.

The left chest deliberately contains both fuel and torches. Basic turtle `suck` cannot select an exact chest slot, so V1 must use bounded pull/classify cycles and a strict chest-content contract: only configured fuel items and configured torch items belong in that chest. If the requested resource cannot be obtained without filling the turtle, stop at base with `NO_FUEL_SUPPLY` or `NO_TORCHES`; do not loop forever. This limitation should be tested with fuel-first and torch-first chest ordering.

### Base layout recommendation

V1 uses two required chests and one optional chest around the surface origin:

```text
             mining direction
                    ^
                    | 4 clear level blocks, then 3x3 stairs
                    |
 supply chest  S -- T -- O  primary ore/output chest
                    B       optional bulk chest behind

S: fuel + torches only
O: ores/valuables; all inventory returned to base when bulk separation is off
B: cobblestone, gravel, dirt, deepslate, and configured bulk output
```

All directions are relative to the turtle's initial forward facing. The turtle turns in place to service each chest and must return to the initial facing before entering the mine.

Inventory backlog:

- [ ] **MVP / P0** Implement occupied-slot count, free-slot count, and consolidation. — **AI-2**
- [ ] **MVP / P0** Trigger service at `occupiedSlots >= returnThreshold`. — **AI-2**
- [ ] **MVP / P0** Implement item-ID quota accounting across arbitrary slots. — **AI-2**
- [ ] **MVP / P0** Implement classification-based routing to the right primary chest and optional rear bulk chest. — **AI-2**
- [ ] **MVP / P0** Implement verified partial/excess unloading with no world-dropping fallback outside the explicit branch-end cobblestone rule. — **AI-2**
- [ ] **MVP / P0** Without a rear bulk chest, eject only excess `minecraft:cobblestone` at each completed branch endpoint, after preserving up to 64 when paving is enabled; verify count deltas and fail with `EJECT_FAILED` on incomplete ejection. — **AI-2**
- [ ] **MVP / P0** Distinguish `NO_SUPPLY_CHEST`, `NO_OUTPUT_CHEST`, `NO_BULK_CHEST`, `CHEST_FULL`, and generic `UNLOAD_FAILED`. — **AI-2**
- [ ] **MVP / P0** Persist the resume checkpoint before moving home. — **AI-2**
- [ ] **MVP / P0** Handle threshold reached while descending stairs, in a floor main tunnel, in either branch phase, and at any vein depth. — **AI-2**
- [ ] **MVP / P0** Ensure no new vein discovery occurs once unwind has been requested. — **AI-2**
- [ ] **MVP / P0** Refuel from allowed items pulled from the left supply chest until the resume fuel invariant is satisfied. — **AI-2**
- [ ] **MVP / P0** Restock configured torches from the left supply chest and verify the minimum departure count. — **AI-2**
- [ ] **MVP / P0** Bound mixed-supply pull/classify attempts and fail safely when chest ordering/content prevents a quota from being met. — **AI-2**
- [ ] **MVP / P1** Preserve up to 64 `minecraft:coal` and 64 `minecraft:torch` by default; preserve up to 64 `minecraft:cobblestone` exclusively for placement when paving is enabled. — **AI-1**
- [ ] **MVP / P1** Restore the original selected slot after inventory operations. — **AI-1**
- [ ] **MVP / P1** Verify all received supply item IDs and quantities. — **AI-1**
- [ ] **MVP / P1** When bulk separation is disabled, eject excess cobblestone only at completed branch endpoints and route all remaining inventory safely to the right chest at base. — **AI-1**
- [ ] **MVP / P1** When bulk separation is enabled, require and verify the rear chest before departure. — **AI-1**
- [ ] **LATER / P2** Support keep rules by tag and acceptable substitutes such as cobbled deepslate. — **AI-1**
- [ ] **EXPERIMENTAL / P3** Evaluate a deterministic inventory peripheral for direct fuel/torch slot selection. — **AI-1**

## 9. Fuel design

### Safety invariant

Before any movement away from safety, require:

```text
usable fuel >= exact route cost from proposed pose to home + reserve
```

“Usable fuel” includes the current internal fuel plus only fuel items the policy is permitted to consume. The implementation should normally refuel just enough to meet the invariant rather than burn every fuel item immediately.

Route cost components are explicit:

- Current vein route depth back to its tunnel checkpoint.
- Remaining straight branch distance to the junction.
- Required vertical normalisation at the junction.
- Floor main-tunnel distance to the active landing.
- Exact recorded staircase centreline climb cost from the active landing to the stair mouth, plus four moves back to the base. With eight forward/down slices per floor, each completed floor segment costs 16 movement fuel to climb; temporary lateral slice sweeps add their own reversible excursion cost while carving.
- Configured reserve.

The reserve default remains 100. It is extra margin, not a replacement for route cost.

### Decisions

- If fuel is unlimited, skip numeric checks but preserve the same control flow and report `unlimited` safely.
- If fuel is below the invariant, attempt configured auto-refuel.
- If refuelling restores the invariant, continue.
- If the turtle can still reach home but cannot safely mine another block, request return immediately.
- If it cannot safely reach home even after consuming permitted inventory fuel, stop with `NO_FUEL` before making another outward move.
- At base, first pull configured fuel from the left supply chest and refuel. Departure to resume requires enough fuel for the four-block entry, staircase descent, floor route to the checkpoint, a complete return from that checkpoint, the reserve, and one bounded work step. Otherwise remain at base.

Fuel backlog:

- [ ] **MVP / P0** Implement exact `costHome(state)` for each valid phase. — **AI-2**
- [ ] **MVP / P0** Include vein breadcrumb depth in `costHome`. — **AI-2**
- [ ] **MVP / P0** Enforce the invariant before every move that can increase home cost. — **AI-2**
- [ ] **MVP / P0** Turn failed refuel into return/stop behaviour, never a warning followed by continued outward mining. — **AI-2**
- [ ] **MVP / P0** Restore selected slot after testing or consuming fuel. — **AI-2**
- [ ] **MVP / P1** Use `refuel(0)` to verify configured fuel items where appropriate. — **AI-1**
- [ ] **MVP / P1** Handle the string value `unlimited` everywhere fuel is displayed or compared. — **AI-1**
- [ ] **MVP / P1** Track actual fuel delta rather than assuming every requested move consumed one unit. — **AI-1**
- [ ] **MVP / P1** Check resume-trip affordability before leaving base. — **AI-1**
- [ ] **MVP / P0** Refill the internal fuel buffer and physical emergency-fuel quota from the left supply chest during every base service. — **AI-2**
- [ ] **NEXT / P2** Estimate job completion fuel for status only; never use the estimate in place of the safety invariant. — **AI-1**

## 10. Ore detection and vein design

CC:Tweaked block inspection can provide a block name, state, and tags. Classification order should be:

1. Explicit ignore name/tag: reject.
2. Explicit configured name/tag: accept.
3. Mode-specific configured tag or name-pattern rule: accept/reject.
4. Otherwise reject.

The built-in defaults should be deliberately small. Use common ore tags when present, the `_ore` suffix as a fallback, and explicit overrides. Do not embed a modpack catalogue.

Ore discovery may occur during shaft or floor work, but V1 must not launch a vein excursion from the middle of a 3×3 staircase sweep. Record the candidate, finish restoring the current slice's centre-bottom pose, commit that checkpoint, and then let the same turtle execute the ore work. This creates the future shaft-miner/ore-gatherer hand-off boundary without adding a second turtle in V1.

### Iterative vein traversal

Use bounded depth-first search because DFS naturally keeps the turtle close to its current route and needs less frontier memory than breadth-first search. Implement it with explicit tables, not Lua recursion.

For every candidate neighbour:

1. Derive its world coordinate.
2. Skip it if visited, beyond `maxRadius`, or the vein block limit is reached.
3. Inspect and classify it.
4. Check inventory pressure and fuel-to-home invariant.
5. Persist intent, dig, and attempt the move.
6. Only after successful movement, push the inverse action onto the route and add the new node to the DFS stack.
7. If movement fails after digging, record a typed error and do not invent a new pose.

When discovery completes or aborts, pop inverse actions until the exact checkpoint pose and facing are restored. Assert equality with the saved checkpoint before resuming the tunnel state machine.

Recommended defaults:

- `maxBlocks = 64` ore blocks per vein.
- `maxRadius = 8` blocks from the tunnel checkpoint, using Manhattan distance for a conservative boundary.
- Explore all six adjacent directions.
- Accept any adjacent block that independently passes the ore classifier; do not require exact name equality.

Vein backlog:

- [ ] **MVP / P0** Implement coordinate-key visited tracking. — **AI-2**
- [ ] **MVP / P0** Implement iterative DFS frontier and inverse route stack. — **AI-2**
- [ ] **MVP / P0** Save and assert checkpoint pose/facing. — **AI-2**
- [ ] **MVP / P0** Queue shaft ore candidates until the 3×3 slice returns to its canonical centre-bottom checkpoint. — **AI-2**
- [ ] **MVP / P0** In V1, execute queued ore work on the same turtle before the next shaft slice; no remote assignment or second worker exists. — **AI-2**
- [ ] **MVP / P0** Add max-block and max-radius guards. — **AI-2**
- [ ] **MVP / P0** Check inventory and fuel before every new vein edge. — **AI-2**
- [ ] **MVP / P0** On inventory/fuel return, unwind before travelling home. — **AI-2**
- [ ] **MVP / P0** Treat any failed inverse movement as fatal `VEIN_RETURN_BLOCKED`. — **AI-2**
- [ ] **MVP / P1** Classify ore using explicit names, tags, patterns, and ignore rules. — **AI-1**
- [ ] **MVP / P1** Preserve traversal state in the persistent snapshot. — **AI-2**
- [x] **MVP / P1** Report cap exhaustion and continue the tunnel only after successful unwind. — **AI-1** `VeinTraversal` reports cap exhaustion through the coordinator callback only after exact checkpoint unwind succeeds; failed unwind remains fatal and suppresses the report. `tests/vein_traversal.lua` covers both outcomes.
- [ ] **NEXT / P2** Record ore counts by block/item type. — **AI-1**
- [ ] **NEXT / P2** Improve ore grouping when stone/deepslate variants or modded variants touch. — **AI-1**
- [ ] **LATER / P3** Add modpack-specific classifier packs as optional user files. — **AI-1**

## 11. Digging, entities, liquids, paving, and lighting

### Falling blocks

- [ ] **MVP / P0** Use a shared bounded dig-clear loop for forward/up/down. — **AI-2**
- [ ] **MVP / P0** Stop after `digRetries` or a time limit with `BLOCKED`/`UNBREAKABLE_BLOCK`. — **AI-2**
- [ ] **MVP / P1** Re-inspect between retries so logs can identify the current block. — **AI-1**
- [ ] **MVP / P1** Reset the retry counter only when the observed block changes, allowing a bounded sequence of gravel/sand without an infinite stream. — **AI-1**

### Entities

- [ ] **MVP / P0** If movement fails with no solid block detected, attempt at most `entityRetries` attacks/waits. — **AI-2**
- [ ] **MVP / P0** Stop with `ENTITY_BLOCKED` after the limit; never attack forever. — **AI-2**
- [ ] **MVP / P1** Print a short warning so nearby players can move before the final retry. — **AI-1**

### Liquids

Safe V1 behaviour is to stop. Turtles cannot reliably solve every flowing-water/lava geometry, and liquid detection may be mod/version dependent.

- [ ] **MVP / P0** When movement fails with no solid block and entity recovery fails, classify the condition as `UNKNOWN_OBSTRUCTION` or `LIQUID` when inspection data supports it, persist, and stop. — **AI-2**
- [ ] **NEXT / P2** Improve water/lava identification using returned block/fluid information available in the target CC:Tweaked version. — **AI-1**
- [ ] **EXPERIMENTAL / P3** Prototype bounded fluid plugging behind a disabled feature flag and only with a guaranteed return path. — **AI-1**

### Paving

- [ ] **MVP / P1** Keep paving optional and disabled by default. — **AI-1**
- [ ] **MVP / P1** Place only explicitly allowed items. — **AI-1**
- [ ] **MVP / P1** When paving is disabled, perform no paving selection or placement; retain only the independently configured mandatory main-shaft backfill reserve. — **AI-1**
- [ ] **MVP / P1** When paving is enabled, treat the retained cobblestone quota as consumable paving working stock; never select or place fuel, torches, ores, unknown items, or other protected inventory. — **AI-1**
- [ ] **MVP / P1** Treat “no paving material” as a warning when paving is optional; never substitute ore or arbitrary inventory items. — **AI-1**
- [ ] **NEXT / P2** Make paving-required mode stop at base for resupply rather than continuing over gaps. — **AI-1**

### Lighting

Torch placement is an MVP requirement. A route carries a fixed outbound frame, so “right” remains stable even when the turtle later faces home.

- Staircase: from the right-middle sweep position, carve/place into a niche beyond the outer right wall so the 3-wide passage stays clear. Never place on a landing slice, because the floor main tunnel exits to that side.
- Floor main tunnel: at the configured height, carve a one-block torch niche in the right wall and place into it.
- Branch: carve the same right-side niche relative to that branch's outbound direction.
- Return, unwind, climb, and service travel: never place torches.

The default cadence is every four stair slices and every eight floor-tunnel blocks. Torch placement is attempted only after the target position and canonical return path are known. A placement helper must restore the exact pose/facing from which it was called. If a niche reveals ore, queue it and finish restoring the lighting checkpoint before starting a vein excursion.

- [ ] **MVP / P0** Implement a route-frame right-side helper independent of current facing. — **AI-2**
- [ ] **MVP / P0** Implement right-side torch/niche placement with exact pose/facing restoration. — **AI-2**
- [ ] **MVP / P0** Place staircase torches only on the outer right wall, never in the cleared 3×3 passage. — **AI-2**
- [ ] **MVP / P0** Skip torch placement on every landing slice so the right-turn floor entrance remains unobstructed. — **AI-2**
- [ ] **MVP / P0** Place floor-main and branch torches only on their outbound right wall. — **AI-2**
- [ ] **MVP / P1** Apply the configured stair/tunnel intervals by route distance, not global move count. — **AI-1**
- [ ] **MVP / P1** Count and persist torches placed so restart does not duplicate the same placement checkpoint. — **AI-1**
- [ ] **MVP / P0** When the torch quota falls below the minimum needed for the current leg, finish the safe checkpoint and return for resupply. — **AI-2**
- [ ] **MVP / P0** If the left chest cannot supply the minimum, stop at base with `NO_TORCHES`. — **AI-2**
- [ ] **NEXT / P2** Support separate main/branch intervals or adaptive spacing if playtesting shows the tunnel cadence is unsuitable. — **AI-1**

## 12. Failure and recovery strategy

Every fatal condition follows the same sequence:

1. Stop issuing movement/dig commands.
2. Set `status="error"` with a stable error code, message, pose, phase, and timestamp/sequence.
3. Persist state and preserve the previous valid backup.
4. Print a compact explanation and the safest operator action.
5. Exit non-zero/false without continuing blindly.

Recommended error codes:

| Code | Meaning | Automatic action |
|---|---|---|
| `NO_FUEL` | Cannot satisfy route-home invariant | Stop; if already at base, request fuel. |
| `NO_FUEL_SUPPLY` | Left supply chest cannot provide enough permitted fuel | Stay at base and stop. |
| `NO_TORCHES` | Left supply chest cannot meet the minimum torch quota | Stay at base and stop. |
| `CHEST_FULL` | Verified remainder after output drop | Stay at base and stop. |
| `NO_SUPPLY_CHEST` | Required left fuel/torch chest absent | Stay at base and stop. |
| `NO_OUTPUT_CHEST` | Required right primary output chest absent | Stay at base and stop. |
| `NO_BULK_CHEST` | Bulk separation enabled but rear chest absent | Stay at base and stop. |
| `EJECT_FAILED` | Branch-end cobblestone count did not decrease by the requested amount | Stop at the branch endpoint without starting the upper return pass. |
| `UNLOAD_FAILED` | Drop failed for another reason | Stay at base and stop. |
| `INVENTORY_CRITICAL` | Full inventory plus required digging/collection | Stop before digging. |
| `BLOCKED` | Movement blocked after bounded recovery | Persist exact pose and stop. |
| `UNBREAKABLE_BLOCK` | Detected block cannot be dug | Persist inspected block and stop. |
| `ENTITY_BLOCKED` | Entity remains after bounded retries | Stop and allow operator intervention. |
| `LIQUID` | Liquid or suspected fluid path | Stop in V1. |
| `VEIN_RETURN_BLOCKED` | Cannot reverse an excursion edge | Stop immediately. |
| `POSITION_ERROR` | Actual state violates a phase invariant | Stop immediately. |
| `POSITION_UNCERTAIN` | Reboot found an uncommitted physical action | Require operator reconciliation. |
| `STATE_CORRUPT` | No valid snapshot/backup | Do not reset automatically. |
| `CONFIG_INVALID` | Invalid or incompatible job config | Do not start movement. |

Recovery commands:

- [ ] **MVP / P1** `miner` starts a new run only when no active/incomplete state exists; otherwise it prints recovery guidance. — **AI-1**
- [ ] **MVP / P1** `miner status` displays run state, pose, certainty, progress, fuel, inventory pressure, and last error without movement. — **AI-1**
- [ ] **MVP / P1** `miner resume` resumes only a validated state with known pose. — **AI-1**
- [ ] **NEXT / P1** `miner home` returns a known-pose turtle along a valid recorded route. — **AI-1**
- [ ] **NEXT / P1** `miner reset` requires explicit confirmation and is allowed only at a physically verified origin. — **AI-1**
- [ ] **NEXT / P1** Add an operator reconciliation flow for a single pending move/turn; never guess automatically. — **AI-3**

## 13. Status and statistics

Keep each routine status line short enough for a standard turtle terminal. Prefer one-line phase updates and reserve multiple lines for fatal errors.

Examples:

```text
[MAIN] pair 5/20  step 2/3
[STAIR] floor 2/4  step 6/8
[FLOOR] 2/4  landing y=-16
[BRANCH] L 17/30 out
[VEIN] iron 8/64  r=4
[INV] 14/16 -> return
[RETURN] branch -> junction
[UNLOAD] ok; 2 kept
[RESUME] L 17/30 out
```

- [ ] **MVP / P2** Track blocks dug, ore blocks dug, veins started, fuel used, service trips, branch pairs completed, and active runtime. — **AI-1**
- [ ] **MVP / P2** Track stair slices completed, floors completed, and torches placed. — **AI-1**
- [ ] **MVP / P2** Update statistics after confirmed actions only. — **AI-1**
- [ ] **MVP / P2** Make statistics writes part of the main state snapshot rather than a second failure-prone transaction. — **AI-1**
- [ ] **NEXT / P2** Track ore by item/block type, ore per fuel, ore per tunnel, and ore per active hour. — **AI-1**
- [ ] **NEXT / P2** Separate paused/server-off time from active runtime where the local clock allows it. — **AI-1**
- [ ] **LATER / P3** Export machine-readable job summaries. — **AI-1**

Statistics are observational: a statistics failure must not cause a navigation action or obscure a safety error.

## 14. Recommended project structure

Avoid both a monolith and one-function files:

```text
oreMiner/
├── miner.lua          # CLI, lifecycle, high-level state machine
├── config.lua         # User configuration only
├── navigation.lua     # Movement authority, pose, routes, bounded obstruction handling
├── resources.lua      # Chest routing, quotas, fuel/torch resupply, base service
├── mining.lua         # Single-turtle shaft/floor/ore phases and vein traversal
├── state.lua          # Validation, snapshots, intent/commit persistence
└── tests/
    ├── mock_turtle.lua
    ├── test_navigation.lua
    ├── test_resources.lua
    ├── test_mining.lua
    └── test_state.lua
```

Six runtime files are justified by distinct responsibilities. Do not add networking abstractions, dependency-injection frameworks, or fleet interfaces. The only future-facing seam needed now is that the high-level miner requests actions through navigation/resources rather than calling global turtle APIs everywhere.

### Future dedicated-job boundary without V1 fleet code

V1 is strictly single-turtle: the same turtle executes every phase in sequence and owns one local state file. There is no worker discovery, assignment, messaging, reservation, collision avoidance, or shared controller.

Internally, keep these work domains explicit so they can become dedicated roles later:

- **Shaft work:** surface entry, 3×3 staircase slices, landings, and verified climb route.
- **Floor work:** level main tunnel, junctions, branches, and floor completion.
- **Ore-gathering work:** exposed-block classification, bounded vein excursions, and checkpoint unwind.
- **Hauling/service work:** return routes, chest routing, fuel, torches, and resume delivery.

Each domain should consume an explicit origin/route frame and return a structured status plus durable progress. It must not read another domain's private counters or call raw turtle movement. For V1 these are ordinary local function/module boundaries, not independently scheduled jobs. A later fleet can assign those same bounded work descriptions to different turtles and add ownership/coordination around them.

- [ ] **MVP / P1** Name persistent phases by work domain (`shaft`, `floor`, `ore`, `service`) while keeping one sequential executor. — **AI-2**
- [ ] **MVP / P1** Give every work unit an ID, origin pose, outbound frame, bounds, cursor, and completion status. — **AI-2**
- [ ] **MVP / P1** Keep navigation and storage policy independent of which future role requested the action. — **AI-1**
- [ ] **MVP / P0** Enforce one active turtle/one active work unit in V1; reject any configuration implying multiple workers. — **AI-2**
- [ ] **LATER / P1** Extract role-specific executors only when multi-turtle work begins. — **AI-3**

## 15. Prioritised implementation backlog

### Checklist integration rule

`reference/branch_miner_phase1.lua` is the preserved original and `src/branch_miner.lua` is the active working implementation. For every checklist item, inspect the original routine but make runtime changes in the `src/` copy and its focused modules.

- If an implemented module directly replaces behavior already executed by `src/branch_miner.lua`, wire that module into the active path and remove the superseded inline logic before marking the item complete.
- A foundational module may remain deliberately unwired when its consuming phase is a later unchecked dependency. Its focused doc and `docs/STATUS.md` must name that dependency and the exact future integration point.
- Relevant verification must exercise the active `src/branch_miner.lua` path when an item is wired. Unit tests alone are sufficient only for a deliberately deferred building block.
- Never modify the preserved reference file as part of checklist implementation.

### Active execution order

Choose only dependency-ready work. Within that set, complete P0 safety/correctness before P1 capability and P2 quality. The immediate queue is: mandatory main-shaft backfill reserve; numerical configuration validation using the resolved branch-length default of 30; exact known-route home-cost coverage; then the four-block surface entry and 3x3 stairs primitive. Re-evaluate readiness after each item instead of skipping an unmet prerequisite.

### Foundation and safety kernel

- [ ] **MVP / P0 — F01** Define pose, phase, result, and error-code contracts. — **AI-2**
- [ ] **MVP / P0 — F02** Build a deterministic mock turtle with configurable action success/failure. — **AI-2**
- [ ] **MVP / P0 — F03** Implement navigation wrappers and prohibit raw movement elsewhere. — **AI-2**
- [ ] **MVP / P0 — F04** Implement exact pose/facing updates and invariant assertions. — **AI-2**
- [ ] **MVP / P0 — F05** Implement bounded dig/entity retry policy. — **AI-2**
- [ ] **MVP / P0 — F06** Implement route-cost fuel invariant and unlimited-fuel handling. — **AI-2**
- [ ] **MVP / P0 — F07** Implement structured fatal-stop handling. — **AI-2**
- [ ] **MVP / P1 — F08** Implement config load, validation, and defaults. — **AI-1**

### Pattern miner

- [ ] **MVP / P1 — M01** Implement the explicit mining phase state machine. — **AI-1**
- [ ] **MVP / P0 — S01** Implement the 3×3 stair-slice sweep, centreline descent, and exact inverse climb. — **AI-2**
- [ ] **MVP / P0 — S02** Move four surface blocks, descend exactly eight slices, then assert and save the first floor landing. — **AI-2**
- [ ] **MVP / P0 — S03** Return from a landing to the surface using only the recorded staircase. — **AI-2**
- [ ] **MVP / P0 — S04** Resume from the surface to the exact active landing without digging. — **AI-2**
- [ ] **MVP / P1 — S05** Advance the floor index only after the prior floor returns to its landing and commits complete. — **AI-1**
- [ ] **MVP / P1 — M02** From the landing, turn right and mine a two-high straight floor main-tunnel segment. — **AI-1**
- [ ] **MVP / P1 — M03** Mine a left branch outbound/lower and return/upper. — **AI-1**
- [ ] **MVP / P1 — M04** Mirror the same branch logic for the right side without duplicate algorithms. — **AI-1**
- [ ] **MVP / P1 — M05** Assert canonical junction pose after each side and canonical forward pose after each pair. — **AI-1**
- [ ] **MVP / P1 — M06** Add lower main-tunnel scans and final upper main-tunnel scan on normal return. — **AI-1**
- [ ] **MVP / P2 — M07** Add optional protected-material paving. — **AI-1**
- [ ] **MVP / P0 — M08** Place interval torches only on each route's outbound right wall. — **AI-2**

### Inventory, home, and resume

- [ ] **MVP / P0 — R01** Implement consolidation and threshold-based pressure. — **AI-2**
- [ ] **MVP / P0 — R02** Capture an exact resume checkpoint and logical cursor. — **AI-2**
- [ ] **MVP / P0 — R03** Return branch checkpoint -> junction -> floor landing -> surface origin over known-clear geometry. — **AI-2**
- [ ] **MVP / P0 — R04** Detect and verify the left supply, right primary output, and enabled rear bulk chest. — **AI-2**
- [ ] **MVP / P0 — R05** Route ores/bulk output with item-ID rules and partial-drop verification; without a rear chest, perform the verified branch-end cobblestone ejection rule. — **AI-2**
- [ ] **MVP / P0 — R06** Navigate surface origin -> active landing -> checkpoint and restore facing/next action. — **AI-2**
- [ ] **MVP / P0 — R07** Validate fuel for the complete resume-and-return commitment before departing base. — **AI-2**
- [ ] **MVP / P0 — R08** Refuel and restock torches from the left chest before departure. — **AI-2**

### Ore and vein safety

- [ ] **MVP / P0 — V01** Implement configurable ore classifier. — **AI-2**
- [ ] **MVP / P0 — V02** Implement iterative DFS with visited/frontier/route tables. — **AI-2**
- [ ] **MVP / P0 — V03** Enforce vein radius and block caps. — **AI-2**
- [ ] **MVP / P0 — V04** Unwind exactly to checkpoint on completion, threshold, low fuel, or bounded cap. — **AI-2**
- [ ] **MVP / P0 — V05** Integrate service requests only after unwind. — **AI-2**
- [ ] **MVP / P1 — V06** Integrate wall/floor/ceiling scans without losing phase orientation. — **AI-1**

### Persistence and recovery

- [x] **MVP / P0 — P01** Implement schema-validated state load/save with temporary and backup files. `src/persistence/state.lua` validates snapshots and commits through a validated `.tmp`, preserving the prior valid snapshot as `.bak`; `tests/persistence_state.lua` verifies roundtrip and backup recovery. — **AI-2**
- [ ] **MVP / P0 — P02** Implement action intent/commit records for every move and turn. — **AI-3**
- [ ] **MVP / P0 — P03** Persist floor/stair cursor, landing poses, mining cursor, resume checkpoint, service stage, and vein route/frontier. — **AI-2**
- [ ] **MVP / P0 — P04** Detect ambiguous pending actions and enter `POSITION_UNCERTAIN`. — **AI-3**
- [ ] **MVP / P1 — P05** Implement `status` and safe `resume` commands. — **AI-2**
- [ ] **MVP / P1 — P06** Add crash-injection tests at every persisted phase boundary. — **AI-2**

### Next release

- [ ] **NEXT / P1 — N01** Add an optional dedicated paving-supply chest if paving becomes required rather than opportunistic. — **AI-1**
- [ ] **NEXT / P1 — N02** Support configurable fuel/torch substitute groups and smarter mixed-supply extraction. — **AI-1**
- [ ] **NEXT / P1 — N03** Add assisted `home`, `reset`, and uncertain-pose reconciliation. — **AI-1**
- [ ] **NEXT / P2 — N04** Improve ore-classifier configuration and diagnostics. — **AI-1**
- [x] **NEXT / P2 — N05** Add detailed statistics and final job summaries. — **AI-1**
- [ ] **NEXT / P2 — N06** Improve liquid identification while retaining stop-safe V1 behaviour. — **AI-1**
- [ ] **NEXT / P2 — N07** Add minimal CLI overrides and help text. — **AI-1**

### Later and experimental

- [ ] **LATER / P3** Add job profiles and multiple base layouts. — **AI-1**
- [ ] **LATER / P1** Add dedicated shaft-miner, floor-miner, ore-gatherer, and hauler/service roles. — **AI-3**
- [ ] **LATER / P3** Add wireless status reporting, Rednet, and controller integration. — **AI-1**
- [ ] **LATER / P3** Add multiple turtles, job queues, roles, scheduling, and collision avoidance. — **AI-1**
- [ ] **LATER / P3** Add GPS as an optional pose verifier, not a V1 dependency. — **AI-1**
- [ ] **LATER / P3** Add remote dashboards/control only after authenticated command and safe-stop designs exist. — **AI-1**
- [ ] **EXPERIMENTAL / P3** Prototype fluid plugging. — **AI-1**
- [ ] **EXPERIMENTAL / P3** Prototype constrained obstacle detours with provable inverse routes. — **AI-1**
- [ ] **EXPERIMENTAL / P3** Evaluate mod peripherals for deterministic mixed-chest item selection. — **AI-1**

## 16. Dependency map

| Item | Depends on | Why |
|---|---|---|
| F03 navigation wrappers | F01, F02 | Contracts and a mock are needed to verify pose changes. |
| F05 bounded recovery | F03 | Recovery acts through the only movement authority. |
| F06 fuel invariant | F03, route-cost functions | Every move must be gated consistently. |
| M01 phase machine | F01, F03, F07, F08 | Mining must use stable state and failure contracts. |
| S01 stair primitive | F03, F05, F06 | Each 3×3 slice is a checked, reversible lateral sweep plus a fuel-gated centreline descent. |
| S02/S03 landings and climb | S01, M01 | Landing identity and the inverse route belong to the phase machine. |
| M02 floor main tunnel | S02, M01 | A floor may begin only from an asserted landing. |
| M03/M04 branches | M01, M02 | Branches build on the straight-tunnel primitive. |
| R01 inventory pressure | F02, F08 | Counts and transfer behaviour need mocking and config. |
| R03 home route | F03, S03, M01, R02 | It requires known floor pose, landing, staircase, and logical phase. |
| R05 unload | R01, R04 | Quotas, chest verification, and explicit bulk classification precede conservative output routing. |
| R08 resupply | R04, R05, F06 | Create inventory space, then pull fuel/torches and verify departure safety. |
| R06 resume | R02, R03, F06 | Resume reverses the service route and must be fuel-safe. |
| V02 vein DFS | F03, F06, V01 | Traversal needs motion, fuel, and classification. |
| V04 unwind | V02, R01 | Abort reasons include resource pressure. |
| P01 state storage | F01, F08 | State and config schemas must exist first. |
| P02 intent/commit | P01, F03 | Transaction records wrap navigation actions. |
| P03 full recovery data | M01, R02, V02, P01 | All sub-state shapes must be stable. |
| P05 resume command | P03, P04, R06 | Resume is safe only after validation and certainty checks. |
| N01/N02 resupply | R05, F06, P03 | Base service, fuel, and restart-safe stages are prerequisites. |

Critical path:

```text
contracts/mock
  -> navigation + fuel invariant
  -> 4-block entry + 3x3 stair slices + landing/climb
  -> floor phase miner
  -> inventory checkpoint/home/unload/resume
  -> iterative vein/unwind
  -> durable intent/commit + restart tests
  -> V1 release
```

Persistence storage can be developed in parallel with the pattern miner, but automatic resume must wait until phase, service, and vein state shapes are stable.

## 17. MVP definition

V1 is complete only when all of these work together:

- Deterministic movement and facing through one navigation authority.
- Exact local pose tracking from a declared origin.
- Validated file configuration and a CLI usable on a normal grey Mining Turtle.
- Strictly one turtle executing shaft, floor, ore, and service work sequentially.
- Surface start, four-block level entry, deterministic 3-wide × 3-tall staircase, and a landing every eight blocks of depth.
- A configurable bounded number of floors, completed sequentially.
- On every floor, a right-turn two-high main tunnel and paired two-high branches using the constrained geometry.
- Main/branch ore scans and bounded iterative vein mining.
- Threshold-based inventory service at 14 occupied slots.
- Required left fuel/torch chest, required right ore/output chest, and optional configured rear bulk chest.
- Automated base refuelling and torch restocking before resume.
- Torch placement at a configurable interval, always on the planned outbound right wall.
- Exact return through the floor landing and staircase to the surface, then back to the saved mining checkpoint, facing, floor, phase, and next action.
- Fuel-to-home invariant and automatic consumption of allowed onboard fuel.
- Bounded gravel/sand/entity handling.
- Stop-safe behaviour for liquids, unbreakable blocks, unexpected obstructions, full/missing chest, and corrupt/uncertain state.
- Local state snapshots, restart at known checkpoints, and refusal to move on ambiguous pose.
- Readable status output and non-critical basic statistics.

### Explicitly excluded from MVP

- Paving-block resupply; V1 only retains available paving material when paving is enabled.
- Arbitrary items in the mixed fuel/torch supply chest; V1 accepts configured supply IDs only.
- GPS and automatic resolution of an ambiguous physical move.
- General pathfinding, obstacle detours, and arbitrary base locations.
- Fluid plugging or navigation through water/lava.
- Wireless modems, Rednet, controller computers, remote control, dashboards, job distribution, multiple turtles, collision avoidance, and fleet scheduling.
- Large hard-coded modpack ore databases.
- GUI, mouse, touch, or Advanced Turtle requirements.
- Multiple active turtles, dedicated worker processes, job assignment, role scheduling, shared work claims, and all other fleet behaviour.

## 18. Testing plan

### Unit-testable logic

- [x] Pose delta for forward/back/up/down in all four facings. — **AI-1** `tests/navigation_pose.lua` compares every movement delta across all four facings against the deterministic fake turtle.
- [x] Left/right turn normalisation, including negative modulo cases. — **AI-1** `tests/navigation_pose.lua` verifies both turn directions from every facing, including west/north wraparound.
- [x] `face()` chooses and records the correct checked turns. — **AI-1** `src/navigation/turn.lua` sequences the shortest checked turns through the coordinator's persistent turn boundary; `tests/navigation_face.lua` covers all facing pairs, failure stopping, and committed pose tracking.
- [x] Inverse route mapping and LIFO unwind. — **AI-2** `src/navigation/action_stack.lua` owns the six-action inverse map and removes records only after literal-success LIFO application; `tests/navigation_action_stack.lua` verifies ordering, invalid actions, and resumable failure state.
- [ ] Exact route-home cost for surface entry, stair slice sub-phases, every floor-mining phase, and vein depth. — **AI-2**
- [ ] 3×3 stair-slice target coordinates and centre-bottom/facing postcondition for all four staircase facings. — **AI-2**
- [ ] Route-frame right-side calculation remains stable during return-facing changes. — **AI-1**
- [x] Unlimited-fuel handling never performs numeric comparisons or formatting. — **AI-1**
- [ ] Refuel policy consumes only permitted items and restores selected slot. — **AI-1**
- [x] Inventory occupied/free counts with mixed partial stacks. — **AI-1**
- [ ] Consolidation with mergeable and incompatible stacks. — **AI-1**
- [x] Keep quotas spread over multiple arbitrary slots. — **AI-1** `src/inventory/chest.lua` allocates each item-ID quota across inventory slots in slot order; `tests/chest_policy.lua` verifies two independent quotas split across nonadjacent slots.
- [x] Partial chest drop leaves a detected remainder. — **AI-1** `src/inventory/chest.lua` returns `CHEST_FULL` with the observed remainder when an exact-count drop transfers only part; `tests/chest_policy.lua` covers direct and unload-path detection.
- [ ] Item routing sends ores right and configured bulk rear when enabled; without a rear chest it ejects only excess cobblestone at a completed branch endpoint and sends all inventory that reaches base right. — **AI-1**
- [ ] Branch-end ejection preserves the configured mandatory backfill reserve across arbitrary slots whether paving is enabled or disabled; optional paving and ejection consume only the excess. — **AI-1**
- [ ] A partial or failed branch-end drop produces `EJECT_FAILED`; ores, unknown items, fuel, torches, and non-cobblestone bulk items are never ejected. — **AI-1**
- [ ] Mixed fuel/torch supply extraction succeeds for both item orders or stops at its bounded limit. — **AI-1**
- [ ] Torch interval and restart cursor never place twice at the same route position. — **AI-1**
- [x] Ore modes, tags, patterns, explicit names, and ignore precedence. — **AI-1**
- [ ] Vein visited keys, radius boundary, and block limit. — **AI-1**
- [ ] Mining phase transitions and `nextAction` idempotence. — **AI-1**
- [x] Config validation boundary values. — **AI-1**
- [ ] State encode/decode, schema validation, temporary-file recovery, and backup fallback. — **AI-2**
- [ ] Every fatal error produces a stopped state with no subsequent action. — **AI-1**

### Mock/simulator tests

- [ ] Move four level blocks from base, reverse them, and return to exact origin/facing. — **AI-1**
- [ ] Carve one 3×3 stair slice and verify all nine target cells are clear. — **AI-1**
- [ ] Finish each stair-slice sub-phase at the expected pose and restore centre-bottom/facing. — **AI-1**
- [ ] Descend eight slices and verify floor 1 landing at depth `y=-8` and forward offset 12 from base. — **AI-1**
- [ ] Complete floor 1, descend eight more slices, and verify floor 2 landing at `y=-16` and forward offset 20. — **AI-1**
- [ ] Climb from floors 1 and 2 through the stair centreline and four-block entry to exact base pose. — **AI-1**
- [ ] Mine a 10-block main tunnel and finish at the expected pose. — **AI-1**
- [ ] Mine one left branch and return to the exact junction pose/facing. — **AI-1**
- [ ] Mine one right branch and return to the exact junction pose/facing. — **AI-1**
- [ ] Mine a complete left/right pair and advance without duplicating a side. — **AI-1**
- [ ] Return home from the main tunnel lower level. — **AI-1**
- [ ] Return home from left and right branch offsets. — **AI-1**
- [ ] Return home from upper branch scan level. — **AI-1**
- [ ] Resume the exact lower/upper branch position, facing, phase, and next action. — **AI-2**
- [ ] Trigger threshold at 14 occupied slots before a tunnel dig. — **AI-1**
- [ ] Trigger threshold at 14 slots inside a vein and prove no further vein node is opened. — **AI-1**
- [ ] Fill the 15th/16th slot during vein unwind and use only the clear return route. — **AI-1**
- [ ] Preserve exactly the available amount up to 64 coal and 64 torches; retain up to 64 cobblestone exclusively for paving placement when paving is enabled. — **AI-1**
- [ ] Handle multiple partial coal/torch stacks. — **AI-1**
- [ ] Detect left supply, right output, and enabled rear bulk chest as present, absent, full, or partially accepting. — **AI-1**
- [ ] Route ore right and cobblestone/gravel rear when separation is enabled. — **AI-1**
- [ ] With the rear chest disabled, eject excess cobblestone at each completed branch endpoint and route all inventory that reaches base right. — **AI-1**
- [ ] Refuel and restock torches from the left chest, then restore forward facing. — **AI-1**
- [ ] Stop at base when fuel is absent, torches are absent, or unsupported items prevent bounded resupply. — **AI-1**
- [ ] Refuse one outward move when it would violate the fuel invariant. — **AI-2**
- [ ] Auto-refuel and then permit that move when sufficient allowed fuel exists. — **AI-1**
- [ ] Stop when onboard fuel still cannot make home safe. — **AI-1**
- [ ] Treat unlimited fuel as safe without errors. — **AI-1**
- [ ] Clear a bounded column of falling gravel/sand. — **AI-1**
- [ ] Stop when falling blocks exceed the retry/time budget. — **AI-1**
- [ ] Stop on bedrock/protected/unbreakable block. — **AI-1**
- [ ] Clear a transient entity and stop on a persistent entity. — **AI-1**
- [ ] Stop safely on suspected water/lava/unknown non-solid obstruction. — **AI-1**
- [ ] Place stair, main, and left/right branch torches only on the planned outbound right wall. — **AI-1**
- [ ] Keep all nine staircase passage cells clear at torch slices and place no torch at a landing slice. — **AI-1**
- [ ] Resume across a torch checkpoint without placing a duplicate. — **AI-1**
- [ ] Find ore in wall, floor, ceiling, and forward excavation. — **AI-1**
- [ ] Traverse a branching six-direction vein and restore checkpoint orientation. — **AI-1**
- [ ] Do not revisit coordinates in a cyclic exposed cavity. — **AI-1**
- [ ] Stop vein discovery at max radius and max blocks, then unwind. — **AI-1**
- [ ] Inject a movement failure on every inverse edge and verify fatal stop. — **AI-1**
- [ ] Inject restart before and after every phase transition. — **AI-1**
- [ ] Inject restart during surface entry, every stair-slice sweep phase, floor landing, main mining, branch outbound, branch upper return, vein traversal, route unwind, stair climb, unloading, resupply, and resume travel. — **AI-2**
- [ ] Load a state with a pending move/turn and verify `POSITION_UNCERTAIN` with zero movement. — **AI-2**
- [ ] Corrupt the main state file and recover from a valid backup. — **AI-2**
- [ ] Corrupt both files and verify `STATE_CORRUPT` with zero movement. — **AI-2**

### In-world integration tests

Run these first in a controlled test gallery with short tunnels, visible coordinates, abundant fuel, and replaceable contents:

- [ ] Confirm the physical origin/facing, left fuel/torch chest, right ore/output chest, and optional rear bulk chest. — **AI-1**
- [ ] Move exactly four blocks forward before beginning any descent. — **AI-1**
- [ ] Carve a measured 3-wide × 3-tall stair slice without leaving stray blocks in the passage. — **AI-1**
- [ ] Reach the first floor exactly eight blocks below the surface, complete it, and reach the second floor exactly eight blocks lower. — **AI-1**
- [ ] Verify the turtle returns to each floor landing before continuing the staircase. — **AI-1**
- [ ] Mine a 10-block main tunnel. — **AI-1**
- [ ] Mine one left branch. — **AI-1**
- [ ] Mine one right branch. — **AI-1**
- [ ] Verify floor main/branch tunnels are two blocks high and one block wide; verify only the staircase is 3×3. — **AI-1**
- [ ] Verify spacing 3 produces the intended two solid rows between branch centrelines. — **AI-1**
- [ ] Return home from main tunnel. — **AI-1**
- [ ] Return home from left branch lower outbound phase. — **AI-1**
- [ ] Return home from right branch lower outbound phase. — **AI-1**
- [ ] Return home from upper scan phase. — **AI-1**
- [ ] Resume exact position after unload without duplicating/skipping a block or branch. — **AI-2**
- [ ] Trigger inventory return at 14 occupied slots. — **AI-1**
- [ ] Keep/refill up to one coal stack and one torch stack. — **AI-1**
- [ ] At every completed branch endpoint without a rear chest, preserve the configured mandatory backfill reserve and eject only excess cobblestone, regardless of whether optional paving is enabled. — **AI-1**
- [x] Test mixed partial stacks. — **AI-1** `tests/inventory_mixed_partial_stacks.lua` verifies inventory service retention across two partial stacks beside protected fuel/ore and eligible excess, including slot and base-pose restoration.
- [ ] Fill the right output chest and verify the turtle remains safely at base. — **AI-1**
- [ ] Fill the enabled rear bulk chest and verify the turtle remains safely at base. — **AI-1**
- [ ] Remove each required chest in turn and verify its specific error. — **AI-1**
- [ ] Disable the rear chest and verify excess cobblestone is ejected only into each completed branch dead end; verify residual inventory carried home unloads to the right output chest. — **AI-1**
- [ ] Supply coal and torches in both chest orders and verify bounded resupply. — **AI-1**
- [ ] Remove coal or torches and verify safe base stop. — **AI-1**
- [ ] Start with low but recoverable fuel. — **AI-1**
- [ ] Start with insufficient fuel and no usable inventory fuel. — **AI-1**
- [ ] Test unlimited-fuel configuration if available. — **AI-1**
- [ ] Test repeated falling gravel/sand within and beyond the bound. — **AI-1**
- [ ] Encounter bedrock or a known protected block. — **AI-1**
- [ ] Let a mob or player temporarily block movement, then test persistent blockage safely. — **AI-1**
- [ ] Detect/mine ore in a wall, floor, and ceiling. — **AI-1**
- [ ] Mine a deliberately placed connected multi-ID ore vein. — **AI-1**
- [ ] Hit the vein block and radius caps. — **AI-1**
- [ ] Fill inventory during a large vein, unwind, unload, return, and continue correctly. — **AI-1**
- [ ] Reboot while mining at a committed checkpoint. — **AI-1**
- [ ] Reboot while returning home. — **AI-1**
- [ ] Reboot after unload and before resume. — **AI-1**
- [ ] Simulate/construct a pending-action state and verify the turtle refuses automatic recovery. — **AI-1**
- [ ] Encounter water and lava in isolated, controlled tests and verify no blind continuation. — **AI-1**
- [ ] Verify every placed torch is on the route-defined right wall, including left and right branches. — **AI-1**
- [ ] Verify stair torches use outer-right niches and never block the 3×3 passage or right-turn floor entrance. — **AI-1**
- [ ] Complete a short job, perform the final main upper scan, and finish at origin. — **AI-1**

### Release gates

- **Gate A — navigation:** 1,000+ mocked random valid moves/turns with pose equal to the simulated world pose; all injected failures leave pose unchanged.
- **Gate B — pattern:** the four-block entry, every 3×3 stair slice, two sequential floor landings, and floor phases finish at their asserted canonical poses.
- **Gate C — service loop:** threshold, stair climb, classified unload, fuel/torch resupply, descent, resume, and completion pass for stair/main/left/right/upper checkpoints.
- **Gate D — vein:** all cap, failure, low-fuel, and mid-vein inventory cases return exactly to checkpoint or stop without claiming success.
- **Gate E — recovery:** crash injection across every persisted boundary either resumes deterministically or produces a safe certainty/error stop.
- **Gate F — in world:** complete at least one multi-trip job with ore veins and a forced reboot before increasing default job size.

## 19. Principal risks and difficult areas

1. **Crash ambiguity around physical actions.** No local file protocol can prove whether a move completed if power dies between world mutation and state commit. V1 must surface uncertainty instead of promising impossible automatic recovery.
2. **Vein return correctness.** Every extra direction, retry, or opportunistic action increases the chance of losing the checkpoint. A single explicit route stack and strict unwind rule are non-negotiable.
3. **Fuel accounting across excursions.** Simple Manhattan distance is insufficient once the turtle enters a vein. Route-depth cost must be included before each outward edge.
4. **Inventory growth after the threshold.** Different ore drops can consume slots quickly, and falling blocks on return can add items. Two-slot headroom, early abort, and no return-path digging are the mitigation.
5. **Dropped-item accumulation at branch ends.** Planned cobblestone ejection creates world item entities until Minecraft removes or collects them. Eject only at completed dead ends, never in the travel path, and keep the operation bounded and verified.
6. **CC:Tweaked/modpack variation.** Tags, chest block IDs, fuel items, and liquid inspection can vary. Configuration and fail-closed behaviour are safer than clever assumptions.
7. **External world changes.** Players, mobs, flowing blocks, or protection mods can alter a previously clear route. Bounded recovery must not silently create an alternate route.
8. **State-machine idempotence.** Persisting “current offset” without defining whether that step is completed causes duplicated or skipped work. Store `nextAction` and test every reboot boundary.
9. **3×3 stair-slice complexity.** Each net depth step requires a lateral excavation sweep and exact centreline restoration. Every sweep sub-phase needs its own failure/restart test.
10. **Mixed fuel/torch supply ordering.** Basic `suck` cannot request a specific chest slot. V1 needs a strict two-category chest contract, bounded extraction attempts, and safe base stop when a quota is unreachable.
11. **Multi-floor fuel growth.** Travel cost rises by at least 16 centreline moves per completed floor segment, plus four surface-entry moves and the active floor route. Deep-floor departure checks must include the full round trip.
12. **Torch-frame mistakes.** “Right” must come from the route's outbound frame, not current facing, or return passes will place torches on alternating sides.
13. **Future job ownership.** Shaft, floor, ore, and hauling work will eventually be assigned separately. V1 must keep their state boundaries clear without introducing premature fleet coordination.
14. **Statistic accuracy.** `dig` success is not identical to items collected; full inventories, fortune-like mechanics, or external collection can diverge. Treat counts as operational estimates unless item deltas are measured.

## 20. Recommended roadmap

### Milestone 1 — Navigation safety kernel (MVP)

This should be the first implementation milestone and the first approval boundary.

- [x] Define contracts, error codes, phases, and pose invariants. `src/core/contracts.lua` exposes validated pose/result shapes, run status, work-domain, phase, certainty, and fatal-code contracts; `tests/contracts.lua` covers them. — **AI-1**
- [ ] Build the mock turtle. — **AI-1**
- [ ] Implement checked movement/turn wrappers. — **AI-1**
- [ ] Implement bounded forward clearing/entity recovery. — **AI-1**
- [ ] Implement route-cost fuel checks. — **AI-2**
- [ ] Implement and prove one complete 3×3 stair-slice sweep, centreline restoration, and inverse climb in tests. — **AI-1**
- [ ] Prove the four-block surface entry and return-to-origin route entirely in tests. — **AI-1**
- [ ] Do not implement veins, unloading, or full mining loops yet. — **AI-1**

Exit criterion: injected movement failures, low fuel, and obstructions can never update pose incorrectly or cause another blind action.

### Milestone 2 — Deterministic pattern miner (MVP)

- [ ] Add validated configuration. — **AI-1**
- [ ] Add the explicit phase state machine. — **AI-1**
- [ ] Descend eight 3×3 slices to floor 1, save the landing, and later continue to floor 2. — **AI-1**
- [ ] Mine floor main/left/right geometry with canonical-pose assertions. — **AI-1**
- [ ] Return each completed floor to its exact landing before descending again. — **AI-1**
- [ ] Add interval torch placement on the route-defined right wall. — **AI-1**
- [ ] Add basic scans/classification without leaving the tunnel. — **AI-1**
- [ ] Add concise status output. — **AI-1**

### Milestone 3 — Inventory service round trip (MVP)

- [ ] Add threshold/consolidation/keep quotas. — **AI-1**
- [ ] Save a resume checkpoint. — **AI-1**
- [ ] Climb the staircase and reverse the four-block entry to base. — **AI-1**
- [ ] Route ores right and optional bulk output behind. — **AI-1**
- [ ] Without a rear bulk chest, eject verified excess cobblestone at each completed branch dead end while preserving one stack for paving placement when paving is enabled. — **AI-1**
- [ ] Refuel/restock torches from the left chest and resume exactly. — **AI-2**
- [ ] Test service from every stair, floor-main, branch, and scan phase. — **AI-1**

### Milestone 4 — Bounded vein excursions (MVP)

- [ ] Add iterative DFS, visited/frontier/route state, caps, and exact unwind. — **AI-2**
- [ ] Integrate fuel and inventory aborts. — **AI-1**
- [ ] Test large/cyclic/multi-ID veins and all inverse-edge failures. — **AI-1**

### Milestone 5 — Persistence and V1 hardening (MVP)

- [ ] Add state snapshots, backup recovery, and movement intent/commit. — **AI-2**
- [ ] Add `status`/`resume` and certainty rules. — **AI-1**
- [ ] Add crash injection, full error matrix, and in-world release gates. — **AI-2**
- [ ] Ship V1 only after a multi-trip, forced-reboot integration run. — **AI-1**

### V1.1 — Operator recovery and storage tuning (NEXT)

- [ ] Add assisted `home`, `reset`, and uncertain-action reconciliation. — **AI-1**
- [ ] Improve base diagnostics. — **AI-1**
- [ ] Improve mixed fuel/torch extraction or add an optional deterministic inventory peripheral. — **AI-1**
- [ ] Add an optional paving-supply chest if paving becomes mandatory. — **AI-1**

### V1.2 — Mining intelligence (NEXT)

- [ ] Improve ore classifier configuration and grouped variants. — **AI-1**
- [ ] Add detailed statistics and summaries. — **AI-1**
- [ ] Improve liquid identification while retaining safe-stop defaults. — **AI-1**
- [ ] Add minimal CLI overrides. — **AI-1**

### Future fleet phase (LATER)

Only after the single turtle meets its release gates:

- [ ] Extract the V1 work domains into dedicated shaft-miner, floor-miner, ore-gatherer, and hauler/service executors. — **AI-3**
- [ ] Define work ownership, hand-off checkpoints, and completion contracts. — **AI-3**
- [ ] Define versioned job/status messages. — **AI-3**
- [ ] Add wireless/Rednet transport behind an optional adapter. — **AI-1**
- [ ] Add a controller and job queue. — **AI-1**
- [ ] Add turtle identities, leases, heartbeats, and collision zones. — **AI-3**
- [ ] Add GPS as optional verification. — **AI-1**
- [ ] Add dashboards and remote commands with explicit safety policy. — **AI-1**

None of these items should add networking code, multiple active workers, or fleet coordination to V1. V1 remains one turtle running all four work domains sequentially.

## 21. Approval checklist before coding

- [x] Approve branch length 30, 20 branch pairs, and centreline spacing 3. The 30-block default preserves the active/reference baseline; validated configuration may select another supported positive length. — **AI-1**
- [ ] Approve paired left/right branches and the two-level scan route. — **AI-1**
- [ ] Approve a four-block level surface entry followed by a 3-wide × 3-tall diagonal staircase. — **AI-1**
- [ ] Approve one-forward/one-down centreline progress and a floor landing every eight blocks of depth. — **AI-1**
- [ ] Approve four floors as the initial bounded default. — **AI-1**
- [x] Approve paving off by default while retaining a separate configurable cobblestone reserve for mandatory main-shaft backfill. — **AI-1**
- [x] Approve inventory threshold 14 and service targets of 64 coal/64 torches; retain 64 cobblestone by default for mandatory backfill, with optional paving limited to excess stock. — **AI-1**
- [ ] Approve the required left fuel/torch chest and right ore/output chest. — **AI-1**
- [ ] Approve the optional rear bulk chest; without it, eject excess cobblestone at each completed branch dead end and send inventory that reaches base to the right chest. — **AI-1**
- [ ] Approve automated base refuelling and torch restocking in V1. — **AI-1**
- [ ] Approve stair torch interval 4, tunnel interval 8, skipped landing torches, and route-defined right-side placement everywhere. — **AI-1**
- [ ] Approve default ore mode `all` as “all positively classified ores,” with tags/patterns and ignore rules. — **AI-1**
- [ ] Approve vein caps of 64 blocks and radius 8. — **AI-1**
- [ ] Approve persistence in MVP and safe stop on ambiguous pending movement. — **AI-1**
- [ ] Confirm V1 is single-turtle only; future role boundaries do not enable fleet behaviour. — **AI-1**
- [ ] Approve Milestone 1 as the first implementation slice. — **AI-1**

## References

- Supplied baseline script (attached to the planning request).
- [CC:Tweaked turtle API](https://tweaked.cc/module/turtle.html) — movement failure returns, inventory functions, inspection data/tags, and unlimited-fuel semantics.
- [CC:Tweaked filesystem API](https://tweaked.cc/module/fs.html) — local state file operations.
- [CC:Tweaked textutils API](https://tweaked.cc/module/textutils.html) — state serialisation options.
- [Original branch miner README](https://github.com/mingjing04/cc-tweaked-miner/blob/main/README.md) — source concept and intended mining pattern.
- [OpenAI model-selection guidance](https://developers.openai.com/api/docs/guides/model-selection) — cost/capability basis for the AI-1, AI-2, and AI-3 coding recommendations.

