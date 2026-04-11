#!/bin/bash
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%T')]${NC} ${GREEN}$1${NC}"
}

main() {
    log "Starting NVM installation..."

    log "Downloading and running NVM install script..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash

    log "Loading NVM into the current session..."
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    log "NVM installed successfully."
}
if [ ! -d "$HOME/.nvm" ]; then
    main
else
    log "NVM is already installed. Skipping."
fi
