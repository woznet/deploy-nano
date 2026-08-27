# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Ubuntu workstation bootstrap deployed via `curl | bash` from GitHub. Three parts:

- `ubuntu/v4/start-aio-min.sh` — the primary script
- `ubuntu/config/scripts/` — standalone install/helper scripts for end users (see its CLAUDE.md)
- `ubuntu/config/` (everything else) — config files that `start-aio-min.sh` downloads and deploys

## Critical: main is live

- `start-aio-min.sh` never reads local repo files — it downloads config from hardcoded `raw.githubusercontent.com/woznet/deploy-nano/main/ubuntu/config/...` URL constants (defined near the top of the script) and fetches the entire `ubuntu/config/scripts/` directory via the GitHub contents API. Renaming or moving anything under `ubuntu/config/` breaks those URLs — update the constants and any scripts that curl sibling scripts.
- There is no test process; consumers run whatever is on `main`. Verify shell changes with `bash -n` and `shellcheck` before committing.

## Shell conventions

- Standard shebang for all shell scripts: `#!/usr/bin/env bash`
- Run `shellcheck` on every `.sh` file you create or edit and fix its warnings
- `set -e` and `set -o pipefail`; 4-space indent; lowercase snake_case function names
- Kali (`$ID == kali`) branches are legacy — keep them working, but new features are Ubuntu-only

## start-aio-min.sh gotchas

- Under `set -e`, increment counters with `VAR=$((VAR+1))`, never `((VAR++))` (it returns status 1 when the value is 0)
- `run_command` evals single-string arguments — quoting inside those strings is deliberate and fragile
- Route work through `run_command`/`run_non_critical` and the `c_ok`/`c_warn`/`c_fail` console helpers so the log file and summary stay accurate

## Line endings

`.gitattributes` enforces LF for `ubuntu/**` — keep files you create or edit under `ubuntu/` LF, even on this Windows checkout.
