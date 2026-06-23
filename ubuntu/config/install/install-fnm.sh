#!/bin/bash
set -e
set -o pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%T')]${NC} ${GREEN}$1${NC}"
}

FNM_PATH="$HOME/.local/share/fnm"

ensure_shellenv() {
    export FNM_PATH

    case ":$PATH:" in
        *":$FNM_PATH:"*) ;;
        *) export PATH="$FNM_PATH:$PATH" ;;
    esac

    if ! grep -qF 'FNM_PATH="$HOME/.local/share/fnm"' "$HOME/.bashrc"; then
        log "Adding fnm shellenv to ~/.bashrc..."
        echo >>"$HOME/.bashrc"
        echo 'FNM_PATH="$HOME/.local/share/fnm"' >>"$HOME/.bashrc"
        echo 'if [ -d "$FNM_PATH" ]; then' >>"$HOME/.bashrc"
        echo '    export PATH="$FNM_PATH:$PATH"' >>"$HOME/.bashrc"
        echo '    eval "$(fnm env --use-on-cd --shell bash)"' >>"$HOME/.bashrc"
        echo 'fi' >>"$HOME/.bashrc"
    else
        log "fnm shellenv entry already present in ~/.bashrc. Skipping."
    fi

    if command -v fnm >/dev/null 2>&1; then
        eval "$(fnm env --use-on-cd --shell bash)"
    fi
}

main() {
    log "Starting fnm installation..."

    log "Downloading and running fnm install script..."
    curl -fsSL https://fnm.vercel.app/install | bash

    log "Loading fnm into the current session..."
    ensure_shellenv

    log "fnm $(fnm --version) installed successfully."
}

if command -v fnm >/dev/null 2>&1; then
    log "fnm is already installed and on PATH. Skipping."
elif [ -x "$FNM_PATH/fnm" ]; then
    log "fnm binary found at $FNM_PATH but not on PATH - repairing shellenv configuration."
    ensure_shellenv
else
    main
fi
