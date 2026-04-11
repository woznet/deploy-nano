#!/bin/bash
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%T')]${NC} ${GREEN}$1${NC}"
}

main() {
    log "Starting VS Code installation..."

    log "Installing prerequisites..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -qq -y wget gpg

    log "Adding Microsoft GPG key..."
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc |
        sudo gpg --yes --dearmor --output /usr/share/keyrings/packages.microsoft.gpg

    log "Adding VS Code apt repository..."
    echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" |
        sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null

    log "Updating apt and installing VS Code..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -qq -y code

    log "VS Code installed successfully."
}
if ! command -v code >/dev/null 2>&1; then
    main
else
    log "VS Code is already installed. Skipping."
fi
