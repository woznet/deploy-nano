#!/bin/bash
set -e
set -o pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%T')]${NC} ${GREEN}$1${NC}"
}

main() {
    log "Starting Ngrok installation..."

    log "Adding Ngrok GPG key and repository..."
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc |
        sudo tee /etc/apt/keyrings/ngrok.asc >/dev/null
    sudo chmod a+r /etc/apt/keyrings/ngrok.asc

    # A key in /etc/apt/trusted.gpg.d is trusted for *every* repository on the
    # host, not just ngrok's. Remove the copy an earlier run of this script left
    # there -- without this, moving the key scopes nothing on an existing host.
    sudo rm -f /etc/apt/trusted.gpg.d/ngrok.asc

    echo "deb [signed-by=/etc/apt/keyrings/ngrok.asc] https://ngrok-agent.s3.amazonaws.com bookworm main" |
        sudo tee /etc/apt/sources.list.d/ngrok.list >/dev/null

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
