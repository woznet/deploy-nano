#!/bin/bash
set -e
set -o pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%T')]${NC} ${GREEN}$1${NC}"
}

NODE_VERSION="${1:-24}"

main() {
    log "Starting Node.js ${NODE_VERSION}.x installation..."

    log "Adding NodeSource repository for Node.js ${NODE_VERSION}.x..."
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | sudo -E bash -

    log "Installing Node.js..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -qq -y nodejs
    hash -r

    log "Configuring npm global prefix at ~/.npm-global..."
    mkdir -p "$HOME/.npm-global"
    npm config set prefix "$HOME/.npm-global"

    if ! grep -q ".npm-global/bin" "$HOME/.bashrc"; then
        log "Adding ~/.npm-global/bin to PATH in ~/.bashrc..."
        echo '' >>"$HOME/.bashrc"
        echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >>"$HOME/.bashrc"
    else
        log "$HOME/.npm-global/bin PATH entry already present in $HOME/.bashrc. Skipping."
    fi

    export PATH="$HOME/.npm-global/bin:$PATH"

    log "Node.js $(node --version) installed successfully."
}

if command -v node >/dev/null 2>&1; then
    CURRENT_MAJOR=$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo "")
    if [ "$CURRENT_MAJOR" = "$NODE_VERSION" ]; then
        log "Node.js ${NODE_VERSION}.x is already installed. Skipping."
        exit 0
    fi
    log "Found Node.js ${CURRENT_MAJOR}.x; installing requested ${NODE_VERSION}.x..."
fi
main
