#!/bin/bash
set -e
set -o pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%T')]${NC} ${GREEN}$1${NC}"
}

BUN_INSTALL="$HOME/.bun"

ensure_shellenv() {
    export BUN_INSTALL

    case ":$PATH:" in
        *":$BUN_INSTALL/bin:"*) ;;
        *) export PATH="$BUN_INSTALL/bin:$PATH" ;;
    esac

    if ! grep -qF 'BUN_INSTALL="$HOME/.bun"' "$HOME/.bashrc"; then
        log "Adding Bun shellenv to ~/.bashrc..."
        echo >> "$HOME/.bashrc"
        echo 'export BUN_INSTALL="$HOME/.bun"' >>"$HOME/.bashrc"
        echo 'export PATH="$BUN_INSTALL/bin:$PATH"' >>"$HOME/.bashrc"
    else
        log "Bun shellenv entry already present in ~/.bashrc. Skipping."
    fi
}

main() {
    log "Starting Bun installation..."

    log "Downloading and running Bun install script..."
    curl -fsSL https://bun.com/install | bash

    log "Loading Bun into the current session..."
    ensure_shellenv

    log "Bun $(bun --version) installed successfully."
}

if command -v bun >/dev/null 2>&1; then
    log "Bun is already installed and on PATH. Skipping."
elif [ -x "$BUN_INSTALL/bin/bun" ]; then
    log "Bun binary found at $BUN_INSTALL but not on PATH - repairing shellenv configuration."
    ensure_shellenv
else
    main
fi
