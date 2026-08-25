#!/bin/bash
set -e
set -o pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%T')]${NC} ${GREEN}$1${NC}"
}

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

# The installer writes nvm.sh as the last step, so a non-empty nvm.sh - not the
# directory - is what proves an install actually finished. Testing for ~/.nvm
# lets an empty or half-written directory block installation permanently.
nvm_is_installed() {
    [ -s "$NVM_DIR/nvm.sh" ] &&
        (
            # shellcheck source=/dev/null
            . "$NVM_DIR/nvm.sh" >/dev/null 2>&1 &&
                command -v nvm >/dev/null 2>&1 &&
                nvm --version >/dev/null 2>&1
        )
}

load_nvm() {
    # shellcheck source=/dev/null
    \. "$NVM_DIR/nvm.sh"
}

nvm_version() {
    nvm --version
}

main() {
    log "Starting NVM installation..."

    log "Downloading and running NVM install script..."
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash

    log "Loading NVM into the current session..."
    if ! nvm_is_installed; then
        log "NVM install did not produce a usable $NVM_DIR/nvm.sh." >&2
        exit 1
    fi
    if ! load_nvm; then
        log "Failed to load NVM from $NVM_DIR/nvm.sh." >&2
        exit 1
    fi

    log "NVM $(nvm_version) installed successfully."
}

if nvm_is_installed; then
    if ! load_nvm; then
        log "Failed to load NVM from $NVM_DIR/nvm.sh." >&2
        exit 1
    fi
    log "NVM $(nvm_version) is already installed. Skipping."
else
    main
fi
