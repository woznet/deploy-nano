#!/usr/bin/env bash
set -e
set -o pipefail

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

agent_version() {
    local version=''
    if [ -x /usr/sbin/qemu-ga ]; then
        version="$(/usr/sbin/qemu-ga --version 2>/dev/null | head -n1)"
    fi
    if [ -z "$version" ]; then
        version="$(dpkg-query -W -f='${Version}' qemu-guest-agent 2>/dev/null || true)"
    fi
    echo "${version:-(version unknown)}"
}

main() {
    log "Starting QEMU guest agent installation..."

    if command -v systemd-detect-virt >/dev/null 2>&1; then
        VIRT="$(systemd-detect-virt 2>/dev/null || echo none)"
        case "$VIRT" in
            kvm | qemu)
                log "Detected virtualization: $VIRT"
                ;;
            *)
                warn "Virtualization reported as '$VIRT'; the agent will install but cannot connect"
                warn "to the host until a virtio-serial channel (org.qemu.guest_agent.0) is present."
                ;;
        esac
    fi

    log "Installing qemu-guest-agent..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -qq -y qemu-guest-agent

    log "Enabling and starting the qemu-guest-agent service..."
    sudo systemctl enable --now qemu-guest-agent

    if systemctl is-active --quiet qemu-guest-agent; then
        log "qemu-guest-agent is active."
    else
        warn "qemu-guest-agent is installed but not active (no virtio-serial channel?)."
    fi
    systemctl --no-pager --full status qemu-guest-agent || true

    log "QEMU guest agent $(agent_version) installed successfully."
}

if dpkg-query -W -f='${Status}' qemu-guest-agent 2>/dev/null | grep -q "^install ok installed"; then
    log "QEMU guest agent is already installed. Skipping."
else
    main
fi
