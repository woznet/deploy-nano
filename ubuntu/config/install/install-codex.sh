#!/bin/bash
set -e
set -o pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%T')]${NC} ${GREEN}$1${NC}"
}

# install-node.sh only exports PATH inside its own process, so pick up the npm
# global prefix it configures in ~/.bashrc.
rehydrate_path() {
    case ":$PATH:" in
        *":$HOME/.npm-global/bin:"*) ;;
        *) export PATH="$HOME/.npm-global/bin:$PATH" ;;
    esac
    hash -r
}

main() {
    log "Starting Codex CLI installation..."

    if ! command -v npm >/dev/null 2>&1; then
        log "npm not found. Install Node.js first (see install-node.sh)." >&2
        exit 1
    fi

    log "Installing @openai/codex globally via npm..."
    npm install -g @openai/codex

    NPM_BIN="$(npm prefix -g)/bin"
    if [[ ! ":$PATH:" == *":$NPM_BIN:"* ]]; then
        export PATH="$NPM_BIN:$PATH"
    fi

    log "Codex CLI $(codex --version 2>/dev/null | head -n1) installed successfully."
}

# The guard below runs before anything hydrates PATH, so pick up the npm
# global prefix first - otherwise an installed CLI is missed and reinstalled
# on every run.
rehydrate_path
if command -v codex >/dev/null 2>&1; then
    log "Codex CLI is already installed. Skipping."
else
    main
fi
