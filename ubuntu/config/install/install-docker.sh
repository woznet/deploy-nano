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
    log "Starting Docker ecosystem installation..."

    # 1. Install prerequisites safely
    log "Installing prerequisites (curl, ca-certificates)..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -qq -y ca-certificates curl

    # 2. Add Docker's official GPG key
    log "Adding Docker's official GPG key..."
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # 3. Add the Docker apt repository (Using the clean string method)
    log "Configuring the Docker apt repository..."
    source /etc/os-release
    local os_suite="${UBUNTU_CODENAME:-$VERSION_CODENAME}"

    local arch
    arch=$(dpkg --print-architecture)

    local repo_content
    repo_content="Types: deb\nURIs: https://download.docker.com/linux/ubuntu\nSuites: $os_suite\nComponents: stable\nArchitectures: $arch\nSigned-By: /etc/apt/keyrings/docker.asc"

    echo -e "$repo_content" | sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq

    # 4. Install Docker Engine and CLI plugins
    log "Installing Docker Engine and plugins..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -qq -y \
        docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # 5. Download and Install Docker Desktop
    log "Downloading Docker Desktop..."
    local desktop_url="https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb"
    local temp_deb="/tmp/docker-desktop.deb"

    # Download the deb file to the /tmp directory
    curl -fsSL "$desktop_url" -o "$temp_deb"

    log "Installing Docker Desktop (This may take a minute to pull GUI dependencies)..."
    # Installing via apt instead of dpkg ensures all missing GUI dependencies are pulled automatically
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -qq -y "$temp_deb"

    # Clean up the downloaded deb file
    rm -f "$temp_deb"

    # 6. Post-installation convenience
    log "Adding current user ($USER) to the docker group..."
    sudo usermod -aG docker "$USER"

    log "Docker ecosystem installed successfully!"
    echo -e "👉 ${BLUE}Note: You must log out and log back in (or restart) for the 'docker' group permissions to take effect.${NC}"
}

# Execute the main function if Docker is not already installed
if ! command -v docker >/dev/null 2>&1; then
    main
else
    log "Docker already installed. Skipping."
fi
