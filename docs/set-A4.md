# Checklist Set A4

> **AGENT PRE-FLIGHT DIRECTIVE:** 
> 1. Inspect all target files to verify each checklist item is still unresolved before modifying code.
> 2. Skip items already implemented in the current working tree.
> 3. Only execute changes for actively reproduced or verified gaps.

## Checklist

### Set A4 — Idempotency guards — *≈45 min*

**Implement:** Every guard must prove the thing it claims — a working binary on a hydrated `PATH`, or every package the script actually installs — so a second run skips instead of reinstalling
**Findings:** BUG-06, BUG-07, BUG-11
**Files (5):** `install-codex.sh`, `install-copilot.sh`, `install-openclaw.sh`, `install-1password.sh`, `install-nvm.sh`
**Why batched:** all five are "the guard tests the wrong thing"; one shared decision about what a guard must prove.

- [x] **BUG-06** — hydrate `PATH` with `~/.npm-global/bin` (and `hash -r`) **before** the top-level guard in `install-codex.sh:32`, `install-copilot.sh:31`, `install-openclaw.sh:237`. Reuse `rehydrate_path()` from `install-openclaw.sh:110-116`; promote it to the shared helper if B1 lands first.
- [x] **BUG-07** — make `install-1password.sh`'s guard cover both packages (e.g. `dpkg-query` on `1password` and `1password-cli`), or split the script and correct the success message.
- [x] **BUG-11** — replace `install-nvm.sh`'s `[ ! -d "$HOME/.nvm" ]` with a check for a usable `$NVM_DIR/nvm.sh`; report the installed version in the closing log.
- [x] Re-run each script twice back to back; the second run must skip, not reinstall.

**Verify:** double-run each of the 5 on a VM; the second run's transcript must contain the "already installed. Skipping." line and no network fetch.

**Depends on:** A1 (`install-1password.sh` and `install-nvm.sh` are also `pipefail` targets). Blocked in part by D2 — the 1Password GUI decision drives the shape of the BUG-07 guard. B3 later normalises guard *shape* across all 18 scripts, so correct the guards here first; do not normalise a guard you are about to rewrite.

## Code-review Report

### BUG-06 — npm-based guards defeated by the `~/.npm-global` prefix — **Medium**

**Files:** `install-codex.sh:32`, `install-copilot.sh:31`, `install-openclaw.sh:237`

`install-node.sh:27` sets the npm global prefix to `~/.npm-global` and appends the `PATH` line to `~/.bashrc` only (`:29-35`). Ubuntu's `~/.bashrc` returns early for non-interactive shells, so `bash install-codex.sh` starts with `~/.npm-global/bin` **absent** from `PATH`. The top-level guard `command -v codex` therefore misses an already-installed CLI and reinstalls it on every run — defeating the idempotency these guards exist to provide.

`install-openclaw.sh` already has the remedy (`rehydrate_path()`, `:110-116`) but applies it *after* its own guard; the same helper should run before the guard in all three.

### BUG-07 — `install-1password.sh` guard covers only half of what it installs — **Medium**

**File:** `install-1password.sh:49`, guard at `:55`

The script installs `1password` (GUI) **and** `1password-cli`, but skips entirely when `op` exists. A host with the CLI and no GUI never gets the GUI. Separately, installing the desktop app unconditionally is questionable on headless VMs — worth an explicit decision (split the script, or gate the GUI on a desktop session).

### BUG-11 — `install-nvm.sh` guard is a bare directory test — **Low**

**File:** `install-nvm.sh:24`

`[ ! -d "$HOME/.nvm" ]` means a partially-created or empty `~/.nvm` permanently blocks installation, and an existing install is never version-checked or upgraded. Every other script in the set tests for a **working binary**. The pinned installer version (`v0.40.3`, `:16`) is also unreviewed for staleness.

### CONF-06 (context) — Missing PATH-repair branch

The "installed but not on `PATH`" repair branch exists in `bun`/`claude`/`fnm`/`homebrew` but is missing from `pnpm`, `nvm`, `codex`, `copilot`, `openclaw`, which share the failure mode. Four of those five are in this set; the branch itself is rolled out in B3. Hydrating `PATH` before the guard (BUG-06) is the prerequisite, not a substitute.

Files affected: 5 scripts

### D2 (open decision) — 1Password GUI on headless hosts

**Findings:** BUG-07

**Decide:** always install the GUI, split into `install-1password-cli.sh` + `install-1password.sh`, or gate the GUI on a detected desktop session. Feeds the guard fix above — a split script needs two guards and two success messages, a gated GUI needs one guard that knows which half ran.
