#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Define simple color codes for terminal output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%T')]${NC} ${GREEN}$1${NC}"
}

main() {
    log "Starting 1Password and 1Password CLI installation..."

    # 1. Add the GPG key
    log "Adding 1Password GPG key..."
    # Using --yes to prevent gpg from hanging if the key already exists
    curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
        sudo gpg --yes --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg

    # 2. Add the apt repository
    log "Configuring the 1Password apt repository..."
    local arch
    arch=$(dpkg --print-architecture)

    # We use double quotes here so the $arch variable expands correctly
    echo "deb [arch=$arch signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$arch stable main" | \
        sudo tee /etc/apt/sources.list.d/1password.list >/dev/null

    # 3. Configure debsig-verify policy
    # 1Password uses this to verify the digital signatures of their .deb packages
    log "Configuring debsig-verify policies for package security..."
    sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22/

    curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol | \
        sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol >/dev/null

    sudo mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22

    curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
        sudo gpg --yes --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg

    # 4. Install both packages
    log "Updating apt and installing 1Password and CLI..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -qq -y 1password 1password-cli

    log "1Password and 1Password CLI installed successfully!"
}

# Execute the main function
if ! command -v op >/dev/null 2>&1; then
    main
else
    log "1Password CLI already installed. Skipping."
fi
