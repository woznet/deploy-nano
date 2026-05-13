#!/bin/bash
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%T')]${NC} ${GREEN}$1${NC}"
}

main() {
    log "Starting pnpm installation..."

    log "Downloading and running pnpm install script..."
    curl -fsSL https://get.pnpm.io/install.sh | sh -

    log "Loading pnpm into the current session..."
    export PNPM_HOME="$HOME/.local/share/pnpm"
    case ":$PATH:" in
        *":$PNPM_HOME:"*) ;;
        *) export PATH="$PNPM_HOME:$PATH" ;;
    esac

    log "pnpm installed successfully."
}
if ! command -v pnpm >/dev/null 2>&1; then
    main
else
    log "pnpm is already installed. Skipping."
fi
