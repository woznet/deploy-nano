#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e
set -o pipefail

# Define simple color codes for terminal output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
ORANGE_RED='\033[38;5;202m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%T')]${NC} ${GREEN}$1${NC}"
}

warn() {
    echo -e "${BLUE}[$(date +'%T')]${NC} ${ORANGE_RED}$1${NC}" >&2
}

# Script scope, not local to main(): the EXIT trap fires after main() has
# returned, and a local would be out of scope and expand to the empty string.
docker_desktop_deb=''

cleanup() {
    if [ -n "$docker_desktop_deb" ]; then
        rm -f "$docker_desktop_deb"
    fi
}
trap cleanup EXIT

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
    if [ -z "$os_suite" ]; then
        warn "Could not determine the distribution codename from /etc/os-release."
        warn "Neither UBUNTU_CODENAME nor VERSION_CODENAME is set; refusing to"
        warn "write an apt source with an empty 'Suites:' line."
        exit 1
    fi

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
    docker_desktop_deb=$(mktemp --suffix=.deb)

    # Download the deb file to a private temp path; cleanup() removes it
    curl -fsSL "$desktop_url" -o "$docker_desktop_deb"

    log "Installing Docker Desktop (This may take a minute to pull GUI dependencies)..."
    # Installing via apt instead of dpkg ensures all missing GUI dependencies are pulled automatically
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -qq -y "$docker_desktop_deb"

    # 6. Post-installation convenience
    local target_user
    target_user="${SUDO_USER:-$(id -un)}"
    if [ "$target_user" = "root" ]; then
        warn "Invoking user resolved to 'root'; skipping usermod -aG docker."
        warn "Run 'sudo usermod -aG docker <your-user>' to grant docker access."
    else
        log "Adding user ($target_user) to the docker group..."
        sudo usermod -aG docker "$target_user"
    fi

    log "Docker ecosystem installed successfully!"
    warn "Group membership does not apply to the current shell. Log out"
    warn "and back in (or run 'newgrp docker' yourself) before using"
    warn "docker without sudo."
}

# Execute the main function if Docker is not already installed
if ! command -v docker >/dev/null 2>&1; then
    main
else
    log "Docker already installed. Skipping."
fi
