#!/bin/bash
set -e
set -o pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%T')]${NC} ${GREEN}$1${NC}"
}

main() {
    log "Starting Codex CLI installation..."

    if ! command -v npm >/dev/null 2>&1; then
        log "npm not found. Install Node.js first (see install-node.sh)." >&2
        exit 1
    fi

    log "Installing @openai/codex globally via npm..."
    npm install -g @openai/codex

    log "Codex CLI $(codex --version 2>/dev/null | head -n1) installed successfully."
}

if command -v codex >/dev/null 2>&1; then
    log "Codex CLI is already installed. Skipping."
else
    main
fi
