#!/usr/bin/env bash
set -e
set -o pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%T')]${NC} ${GREEN}$1${NC}"
}

BREW_PREFIX="/home/linuxbrew/.linuxbrew"

ensure_shellenv() {
    eval "$("$BREW_PREFIX/bin/brew" shellenv)"

    if ! grep -qF 'brew shellenv' "$HOME/.bashrc"; then
        log "Adding Homebrew shellenv to ~/.bashrc..."
        echo '' >>"$HOME/.bashrc"
        echo "eval \"\$($BREW_PREFIX/bin/brew shellenv)\"" >>"$HOME/.bashrc"
    else
        log "Homebrew shellenv entry already present in ~/.bashrc. Skipping."
    fi
}

main() {
    log "Starting Homebrew installation..."

    log "Installing prerequisites (build-essential, procps, curl, file, git)..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -qq -y build-essential procps curl file git

    log "Downloading and running the Homebrew install script..."
    # Capture first: this is command substitution, not a pipeline, so pipefail
    # cannot help. A failed fetch would otherwise expand to an empty string and
    # `bash -c ""` would exit 0, reporting a successful install that never ran.
    local brew_installer
    if ! brew_installer="$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || [ -z "$brew_installer" ]; then
        log "Failed to download the Homebrew install script."
        exit 1
    fi
    NONINTERACTIVE=1 /bin/bash -c "$brew_installer"

    log "Loading Homebrew into the current session..."
    ensure_shellenv

    # No pipeline here: `brew --version | head -n1` would be a pipefail
    # hazard, and a failing brew silently rendered an empty version string.
    local brew_version
    brew_version="$(head -n1 <<<"$(brew --version 2>/dev/null || echo 'installed')")"
    log "Homebrew $brew_version installed successfully."
}
if command -v brew >/dev/null 2>&1; then
    log "Homebrew is already installed and on PATH. Skipping."
elif [ -x "$BREW_PREFIX/bin/brew" ]; then
    log "Homebrew binary found at $BREW_PREFIX but not on PATH — repairing shellenv configuration."
    ensure_shellenv
else
    main
fi
