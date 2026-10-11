# Turtle autostart

## Purpose

Launch the single-turtle miner when CC:Tweaked boots and use its durable recovery path after a restart.

## Implemented behavior

`git pull` installs `boot.lua` in the repository and a small managed hook at `/startup/oreminer.lua`. CC:Tweaked runs that hook on computer startup. The hook launches the installed `boot.lua`, which switches the shell to the installation directory before starting `miner` and restores the previous directory afterward. This preserves the coordinator's relative `oreMiner/state.json` path.

If `state.json`, its backup, or its temporary commit exists, boot calls `miner resume`. The existing recovery classifier decides whether pose and cursor are safe; it refuses pending movement, corrupt state, incompatible configuration, and unsupported checkpoints before motion. If no snapshot exists, boot opens the normal new-run configuration confirmation. A completed snapshot is passed to `resume`, which leaves the turtle idle. Autostart does not repeat a completed job.

## Public entry points

- `/startup/oreminer.lua` — managed CC:Tweaked boot hook, created by `git pull`.
- `boot.lua` — installation-relative startup dispatcher.
- `miner` and `miner resume` — existing interactive start and saved-run recovery commands.

## Invariants and assumptions

The hook is installed only after the runtime pull succeeds. The installer preserves an unrelated file already named `/startup/oreminer.lua` and reports that autostart needs manual setup. It does not change other files in `/startup/`. A pull of an unchanged commit can repair a missing managed hook. Boot never interprets saved pose itself or bypasses the miner's configuration and recovery checks.

## Dependencies and limitations

CC:Tweaked must allow startup files (`shell.allow_startup`), and disk startup precedence must not suppress the computer's root startup directory. A software check cannot prove what happens on an actual world reload. On the turtle, reboot at a committed checkpoint and verify automatic `resume`; reboot with a pending physical action and verify `POSITION_UNCERTAIN` with no movement. Follow `docs/home-test.md` before claiming the V1 release gate.
