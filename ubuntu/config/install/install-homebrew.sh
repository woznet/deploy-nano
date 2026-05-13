#!/bin/bash
set -e

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
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    log "Loading Homebrew into the current session..."
    ensure_shellenv

    log "Homebrew $(brew --version | head -n1) installed successfully."
}
if command -v brew >/dev/null 2>&1; then
    log "Homebrew is already installed and on PATH. Skipping."
elif [ -x "$BREW_PREFIX/bin/brew" ]; then
    log "Homebrew binary found at $BREW_PREFIX but not on PATH — repairing shellenv configuration."
    ensure_shellenv
else
    main
fi
