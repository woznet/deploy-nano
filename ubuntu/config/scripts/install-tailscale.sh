#!/usr/bin/env bash
set -e
set -o pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%T')]${NC} ${GREEN}$1${NC}"
}

main() {
    log "Starting Tailscale installation..."

    log "Installing prerequisites (curl, ca-certificates)..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -qq -y curl ca-certificates

    log "Downloading and running the Tailscale install script..."
    curl -fsSL https://tailscale.com/install.sh | sh

    log "Tailscale $(tailscale version | head -n1) installed successfully."
    log "Run 'sudo tailscale up' to authenticate this machine."
}
if command -v tailscale >/dev/null 2>&1; then
    log "Tailscale is already installed. Skipping."
else
    main
fi
