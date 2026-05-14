#!/bin/bash
set -e
set -o pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%T')]${NC} ${GREEN}$1${NC}"
}

CLAUDE_BIN="$HOME/.local/bin/claude"

ensure_path() {
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *) export PATH="$HOME/.local/bin:$PATH" ;;
    esac

    if ! grep -qF '.local/bin' "$HOME/.bashrc"; then
        log "Adding ~/.local/bin to PATH in ~/.bashrc..."
        echo '' >>"$HOME/.bashrc"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >>"$HOME/.bashrc"
    else
        log "$HOME/.local/bin PATH entry already present in $HOME/.bashrc. Skipping."
    fi
}

main() {
    log "Starting Claude CLI installation..."

    log "Downloading and running the Claude install script..."
    curl -fsSL https://claude.ai/install.sh | bash

    log "Loading Claude CLI into the current session..."
    ensure_path

    log "Claude CLI $(claude --version 2>/dev/null | head -n1) installed successfully."
}

if command -v claude >/dev/null 2>&1; then
    log "Claude CLI is already installed and on PATH. Skipping."
elif [ -x "$CLAUDE_BIN" ]; then
    log "Claude CLI binary found at $CLAUDE_BIN but not on PATH — repairing PATH configuration."
    ensure_path
else
    main
fi
