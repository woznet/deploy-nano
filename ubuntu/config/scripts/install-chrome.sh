#!/bin/bash
set -e
set -o pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%T')]${NC} ${GREEN}$1${NC}"
}

# Script scope, not local to main(): the EXIT trap fires after main() has
# returned, and a local would be out of scope and expand to the empty string.
temp_deb=''

cleanup() {
    local status=$?
    if [ -n "$temp_deb" ]; then
        rm -f "$temp_deb" || true
    fi
    return "$status"
}
trap cleanup EXIT

main() {
    log "Starting Google Chrome installation..."

    log "Installing prerequisites (curl)..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -qq -y curl

    log "Downloading Google Chrome .deb package..."
    local chrome_url="https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
    # Download to a private temp path; cleanup() removes it on every exit path
    temp_deb=$(mktemp --suffix=.deb)
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
