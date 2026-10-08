# Main tunnel ore scan

## Purpose

Discover classified ore veins exposed around floor main-tunnel cells.

## Implemented behavior

When vein mining is enabled, each newly reached main-tunnel cell is scanned on both side walls, the floor, and the ceiling. The turtle remains at the cell while scanning; side headings are restored with checked turns. `MainTunnelScan.scanCell` stops on the first failed scan callback, and the active coordinator propagates vein return or inventory-service failures. Between intermediate spacing cells, the coordinator retraces the checked edge to preserve the existing branch junction pose, avoiding a changed branch-grid route and duplicate cell scans.

## Public module/API entry points

- `require("src.mining.main_tunnel_scan")`
- `MainTunnelScan.scanCell(ops)` accepts `facing()` and `scan(direction)` callbacks for `left`, `right`, `down`, and `up`; it returns a structured result.
- `src/branch_miner.lua` wires these callbacks to the shared classifier, iterative vein traversal, checked turns/movement, and inventory service.

## Invariants and assumptions

- Scan callbacks use the existing `OreClassifier` and `VeinTraversal` path; this module does not classify blocks or move the turtle itself.
- Side checks restore the original facing before the next scan direction. The module verifies facing after all successful callbacks.
- Any seed excursion must unwind through its recorded breadcrumbs to the main-cell checkpoint before scanning continues.
- Cell scans occur only when `config.vein_mine` is enabled.

## Dependencies and limitations

The scan helper is callback-only. It does not change staircase or branch geometry. The pre-existing coordinator's spacing loop returns to the same canonical junction after each pair; this item scans each cell reached by that loop and preserves that route. A deterministic helper test cannot model Minecraft block drops or external world changes.

## Verification

Run `C:/Users/Game/AppData/Local/Programs/Lua/bin/lua.exe tests/main_tunnel_scan.lua`. Related vein, route-fuel, branch-progress, and active-wiring checks are recorded in `docs/STATUS.md`.
