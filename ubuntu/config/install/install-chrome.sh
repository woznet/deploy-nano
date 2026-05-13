#!/bin/bash
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%T')]${NC} ${GREEN}$1${NC}"
}

main() {
    log "Starting Google Chrome installation..."

    log "Installing prerequisites (curl)..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -qq -y curl

    log "Downloading Google Chrome .deb package..."
    local chrome_url="https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
    local temp_deb
    temp_deb=$(mktemp --suffix=.deb)
    trap 'rm -f "$temp_deb"' EXIT
    curl -fsSL "$chrome_url" -o "$temp_deb"

    log "Installing Google Chrome (pulling missing dependencies)..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -qq -y "$temp_deb"

    log "Google Chrome installed successfully."
}
if ! command -v google-chrome >/dev/null 2>&1; then
    main
else
    log "Google Chrome is already installed. Skipping."
fi
