#!/bin/bash
set -e

# Define simple color codes for terminal output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%T')]${NC} ${GREEN}$1${NC}"
}

if ! command -v az >/dev/null 2>&1; then
    sudo apt update -qq
    sudo apt install -qq -y apt-transport-https ca-certificates curl gnupg lsb-release

    sudo mkdir -p /etc/apt/keyrings
    curl -sLS https://packages.microsoft.com/keys/microsoft.asc |
        gpg --dearmor | sudo tee /etc/apt/keyrings/microsoft.gpg >/dev/null
    sudo chmod go+r /etc/apt/keyrings/microsoft.gpg

    AZ_DIST=$(lsb_release -cs)
    echo "Types: deb
URIs: https://packages.microsoft.com/repos/azure-cli/
Suites: ${AZ_DIST}
Components: main
Architectures: $(dpkg --print-architecture)
Signed-by: /etc/apt/keyrings/microsoft.gpg" | sudo tee /etc/apt/sources.list.d/azure-cli.sources

    sudo apt update -qq
    sudo apt install -qq -y azure-cli

else
    log "Azure CLI already installed. Skipping."
fi
