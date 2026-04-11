#!/bin/bash
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%T')]${NC} ${GREEN}$1${NC}"
}

main() {
    log "Starting Ngrok installation..."

    log "Adding Ngrok GPG key and repository..."
    curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
    echo "deb https://ngrok-agent.s3.amazonaws.com bookworm main" | sudo tee /etc/apt/sources.list.d/ngrok.list >/dev/null

    log "Updating apt and installing Ngrok..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -qq -y ngrok

    log "Configuring user Bash completions for Ngrok..."
    local comp_dir="$HOME/.local/share/bash-completion/completions"
    mkdir -p "$comp_dir"
    ngrok completion bash >"$comp_dir/ngrok"

    log "Ngrok installed successfully."
}
if ! command -v ngrok >/dev/null 2>&1; then
    main
else
    log "Ngrok is already installed. Skipping."
fi
