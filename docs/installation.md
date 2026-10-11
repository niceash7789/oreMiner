# In-game installation and pull

## Purpose

Install the single-turtle oreMiner runtime from GitHub with one command and support a manual, foreground `git pull` for test builds without deploying development-only files to the turtle.

## Implemented behavior

Run the bootstrap from the directory that should contain oreMiner:

```text
mkdir oreMiner
cd oreMiner
wget run https://raw.githubusercontent.com/niceash7789/oreMiner/main/install.lua
```

`install.lua` downloads the repository's read-only `git.lua`, creates `.git_config` for `niceash7789/oreMiner` on `main`, and performs exactly one foreground pull. The pull resolves one GitHub commit, obtains its recursive tree, and downloads only `miner.lua`, `install.lua`, `git.lua`, `config.example.lua`, and Lua modules under `src/`. Tests, plans, reference material, and other development files are excluded to fit normal turtle storage.

All files are downloaded and syntax-checked in a staging directory before installed runtime files change. Existing managed files are moved to a backup during replacement and restored if installation fails. A successful first pull copies `config.example.lua` to the untracked `config.lua`; later pulls retain the live config. `.git_config` records the installed commit and managed file list so a later pull can remove obsolete runtime modules safely.

After installation, edit `config.lua` and run `miner` from the installation directory. To fetch another test build, stop the miner, return to that directory, and run:

```text
git pull
```

## Public entry points

- `install.lua` — bootstrap a public `main`-branch installation and perform one pull.
- `git pull` — perform one manual foreground pull using the local `.git_config`.
- `config.example.lua` — tracked example copied only when `config.lua` is absent.

## Invariants and assumptions

- Pull never downloads or replaces `config.lua`, `.git_config`, or anything under `oreMiner/`.
- Pull does not inspect `oreMiner/state.json`; it preserves the file even when a run is incomplete.
- Every downloaded path is restricted to the runtime allowlist and checked for unsafe path components.
- Every pull is internally consistent: the tree and raw files use one resolved commit SHA even though the test channel follows `main`.
- There is no push, clean update, daemon, background service, token storage, networking between turtles, or fleet behavior.

## Dependencies and current limitations

CC:Tweaked HTTP must be enabled, and the server must permit `api.github.com` and `raw.githubusercontent.com`. The GitHub repository must be public; authentication and private repositories are intentionally unsupported.

This is a test-channel installer and follows `main`; a release should change the bootstrap to a release tag. Updating configuration schema is not automatic. If a newer example adds required fields, compare it with the retained `config.lua` and edit the live file explicitly. The installer cannot prove that no other multishell tab is executing code, so the operator must stop the miner before pulling.

An installation still running an older `git.lua` may reject its own update when saved state is incomplete. After this change is published, rerun the bootstrap command above from the existing installation directory once to replace that client; it retains `config.lua` and saved state.

`tests/installer_pull.lua` supplies deterministic fake filesystem, HTTP, shell, and serialization APIs. It verifies the single bootstrap pull, runtime-only filtering, live config/state preservation, stale managed-file removal, installed-commit recording, and pulling with an incomplete run state.

