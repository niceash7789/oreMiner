# Turtle operator guide

## Purpose

Install and operate the current single-turtle miner in a controlled CC:Tweaked world. This is a V0.9 candidate; the physical release gates in [MINER_PLAN.md](../MINER_PLAN.md) have not been completed.

## Setup

Place the turtle on the surface at its intended origin, facing into the mine. Put a supply chest directly on its left and an ore/output chest directly on its right. If `base.separateBulk = true`, put a bulk-output chest behind it. Stock the left chest with allowed fuel and torches. Keep the path and replaceable test area clear of protected blocks and liquids.

On the turtle, install into its own directory:

```text
mkdir oreMiner
cd oreMiner
wget run https://raw.githubusercontent.com/niceash7789/oreMiner/main/install.lua
```

The installer requires CC:Tweaked HTTP access to GitHub and copies `config.example.lua` to `config.lua` only if a live config is absent. See [installation](installation.md) for update and autostart details.

## Configure a first run

Edit `oreMiner/config.lua` before starting. The tracked example currently requests four floors, an extra 16 stair slices before floor 1, 16 pairs per main side, and length-16 shafts. Those values are larger than a short gallery trial. For the first controlled run, use one floor, zero first-floor offset, one pair per main side, and a short shaft length. Keep `surfaceEntryLength = 4`, `stairWidth = 3`, `stairHeight = 4`, and `branchSpacing = 3` unless the plan explicitly changes them. Check `fuel.reserve`, retained coal/torch counts, and chest settings against the physical setup.

Configuration is validated before movement or inventory use. A present invalid `config.lua` stops startup. Do not change route geometry or configuration while a saved run is active; snapshot compatibility rejects changed settings. See [numeric configuration](numeric-configuration.md) and [fuel and return](fuel-and-return.md).

## Commands

Run these from the `oreMiner` directory on the turtle:

| Command | Action |
| --- | --- |
| `miner` | Show the new-run summary and confirmation, then start mining. |
| `miner status` | Read saved progress, pose certainty, fuel, inventory pressure, and recovery status without moving. |
| `miner resume` | Validate a saved run and continue only from a supported, known checkpoint. |
| `miner home` | Pause a saved run and travel to origin over recorded route cells when pose is known. |
| `git pull` | Update installed runtime files from the configured `main` test channel after stopping the miner. |

The installed startup hook opens the new-run flow if no state exists or attempts `miner resume` when a saved state exists. Check `miner status` after a reboot refusal. `git pull` preserves `config.lua` and `oreMiner/state.json`; compare the new example with your live config before a subsequent run.

## During a run

The turtle checks movement, digging, turning, chest transfers, fuel, and route-home cost. It services inventory at the configured pressure threshold, returns through recorded routes, unloads to the configured chests, restocks from the left, and resumes the saved checkpoint. Torches are placed on the route-defined right side. A temporary lack of fuel or torches at base waits for resupply.

Ctrl+T during active `miner` or `miner resume` requests a graceful stop and runs the checked home path after the current turtle API call finishes. At a shell prompt, use `miner home`. The command can refuse if pose is uncertain, fuel is insufficient, a return cell cannot be cleared, or state cannot be saved. See [home command](home-command.md).

## If it stops or reboots

Run `miner status` first. If the saved pose is known and the cursor is supported, use `miner resume`; if you want to park at base, use `miner home`. Do not manually move or turn the turtle before using either command. A pending move, turn, or dig after reboot produces `POSITION_UNCERTAIN` and prohibits automatic movement. A committed stair-sweep or landing-carve cursor may still refuse mining resume because its dig sub-actions are not fully recorded; `miner home` can use a valid breadcrumb from a known pose, but return still depends on fuel and a traversable recorded path. See [persistence](persistence.md).

For a first physical verification, follow [the controlled gallery sequence](home-test.md). It includes geometry, torches, chest service, a forced reboot, and the multi-trip release gate. Record observed results before treating the miner as unattended-ready.

## Public entry points, invariants, and limits

`miner.lua` launches the coordinator in `src/branch_miner.lua`; `install.lua`, `git.lua`, and `boot.lua` provide installation, updates, and startup. The turtle starts at mine-frame `(0,0,0)` facing the mine. Its left and right chest positions are relative to that initial facing. Saved pose changes only after confirmed movement or turning; return uses recorded cells and a known-route fuel reserve. No GPS or automatic reconciliation of an ambiguous physical action is provided. The current installer follows `main`, not a release tag, and the in-world release gates remain open.
