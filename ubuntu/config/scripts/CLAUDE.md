# ubuntu/config/scripts/

Standalone installer scripts that end users run directly. `start-aio-min.sh` auto-deploys **every file in this directory** to users' `~/dev/scripts` via the GitHub contents API — do not add anything here that should not ship to end users.

## Conventions (match the existing scripts)

- Naming: `install-<tool>.sh`
- Boilerplate: `#!/usr/bin/env bash`, then `set -e` and `set -o pipefail` on separate lines
- Color vars (`GREEN`, `BLUE`, `NC`) and a `log()` helper: `echo -e "${BLUE}[$(date +'%T')]${NC} ${GREEN}$1${NC}"`
- Idempotent: check `command -v <tool>` before installing
- Run as a regular user with inline `sudo` — no root check at the top
- Scripts that curl sibling scripts must use the raw URL base `https://raw.githubusercontent.com/woznet/deploy-nano/main/ubuntu/config/scripts/`
