#!/usr/bin/env bash
#
# enable-gnome-rdp.sh
#
# Enable GNOME's native RDP server ("Remote Login" / headless mode) on Ubuntu
# Desktop, optionally removing xrdp first. Ubuntu 25.10+ dropped GNOME-on-Xorg,
# so xrdp no longer works with GNOME sessions — gnome-remote-desktop is the
# supported replacement and runs on Wayland through gnome-shell.
#
# Designed to be run over SSH on a fresh install. Idempotent: re-running on a
# host that's already configured is safe.
#
# Usage:
#   sudo ./enable-gnome-rdp.sh [options]
#
# Options:
#   -u USERNAME      RDP-layer username (prompts if omitted)
#   -p PASSWORD      RDP-layer password (prompts silently if omitted)
#                    Alternative: set RDP_PASSWORD env var to avoid prompting
#   --keep-xrdp      Don't uninstall xrdp (default: purge it)
#   --no-firewall    Skip UFW 3389/tcp rule even if UFW is active
#   -h, --help       Show this help
#
# Examples:
#   sudo ./enable-gnome-rdp.sh                          # fully interactive
#   sudo ./enable-gnome-rdp.sh -u rdpuser               # prompt for password only
#   sudo RDP_PASSWORD='hunter2' ./enable-gnome-rdp.sh -u rdpuser
#
# Notes:
#   - RDP-layer credentials are SEPARATE from your Linux login credentials.
#     The RDP creds get the connection in the door; after that you log in as
#     your normal Linux user inside the session.
#   - "Remote Login" mode creates a fresh session on connect; no console login
#     is required on the host.

set -euo pipefail

# ---------- defaults ----------
RDP_USER=""
RDP_PASS=""
KEEP_XRDP=0
NO_FIREWALL=0

# ---------- pretty output ----------
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
    BLUE=$(tput setaf 4)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    RED=$(tput setaf 1)
else
    BOLD=""
    RESET=""
    BLUE=""
    GREEN=""
    YELLOW=""
    RED=""
fi

log() { echo "${BLUE}[*]${RESET} $*"; }
ok() { echo "${GREEN}[✓]${RESET} $*"; }
warn() { echo "${YELLOW}[!]${RESET} $*" >&2; }
err() { echo "${RED}[✗]${RESET} $*" >&2; }

usage() {
    sed -n '3,30p' "$0" | sed 's/^# \?//'
}

# ---------- arg parsing ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
    -u)
        RDP_USER="${2:-}"
        shift 2
        ;;
    -p)
        RDP_PASS="${2:-}"
        shift 2
        ;;
    --keep-xrdp)
        KEEP_XRDP=1
        shift
        ;;
    --no-firewall)
        NO_FIREWALL=1
        shift
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        err "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
done

# ---------- preflight ----------
if [[ $EUID -ne 0 ]]; then
    err "Must run as root (use sudo)."
    exit 1
fi

if [[ ! -f /etc/os-release ]]; then
    err "Cannot detect OS (no /etc/os-release)."
    exit 1
fi

# shellcheck disable=SC1091
. /etc/os-release
log "Detected: ${PRETTY_NAME:-unknown}"

if [[ "${ID:-}" != "ubuntu" ]]; then
    warn "This script is intended for Ubuntu. Continuing anyway."
fi

# Warn (don't fail) if older than 25.10 — those versions can still use xrdp.
if [[ -n "${VERSION_ID:-}" ]]; then
    major="${VERSION_ID%%.*}"
    minor="${VERSION_ID##*.}"
    if ((major < 25)) || { ((major == 25)) && ((minor < 10)); }; then
        warn "Ubuntu ${VERSION_ID} predates the GNOME-on-Xorg removal."
        warn "xrdp still works on this release; you may not need this script."
    fi
fi

if ! command -v gnome-shell >/dev/null 2>&1; then
    err "GNOME Shell not found. This script targets Ubuntu Desktop with GNOME."
    exit 1
fi

# ---------- credentials ----------
if [[ -z "$RDP_USER" ]]; then
    read -r -p "RDP username: " RDP_USER
fi

if [[ -z "$RDP_PASS" ]]; then
    if [[ -n "${RDP_PASSWORD:-}" ]]; then
        RDP_PASS="$RDP_PASSWORD"
        log "Using RDP_PASSWORD from environment."
    else
        read -r -s -p "RDP password: " RDP_PASS
        echo
        read -r -s -p "Confirm:      " RDP_PASS2
        echo
        if [[ "$RDP_PASS" != "$RDP_PASS2" ]]; then
            err "Passwords do not match."
            exit 1
        fi
    fi
fi

if [[ -z "$RDP_USER" || -z "$RDP_PASS" ]]; then
    err "Both username and password are required."
    exit 1
fi

# ---------- remove xrdp ----------
if [[ $KEEP_XRDP -eq 0 ]] && dpkg -l xrdp 2>/dev/null | grep -q '^ii'; then
    log "Removing xrdp..."
    systemctl disable --now xrdp xrdp-sesman 2>/dev/null || true
    DEBIAN_FRONTEND=noninteractive apt-get purge -y xrdp xorgxrdp
    DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y
    rm -rf /etc/xrdp /var/log/xrdp* /run/xrdp 2>/dev/null || true
    ok "xrdp removed."
else
    log "xrdp not installed (or --keep-xrdp set); skipping removal."
fi

# ---------- install gnome-remote-desktop ----------
if ! dpkg -l gnome-remote-desktop 2>/dev/null | grep -q '^ii'; then
    log "Installing gnome-remote-desktop..."
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y gnome-remote-desktop
    ok "gnome-remote-desktop installed."
else
    log "gnome-remote-desktop already installed."
fi

if ! command -v grdctl >/dev/null 2>&1; then
    err "grdctl not found after install. Aborting."
    exit 1
fi

# ---------- configure ----------
log "Setting RDP credentials and enabling system-mode RDP..."
grdctl --system rdp set-credentials "$RDP_USER" "$RDP_PASS"
grdctl --system rdp enable
ok "RDP configured."

log "Enabling and starting gnome-remote-desktop.service..."
systemctl enable --now gnome-remote-desktop.service

# ---------- firewall ----------
if [[ $NO_FIREWALL -eq 0 ]] && command -v ufw >/dev/null 2>&1 &&
    ufw status 2>/dev/null | grep -q "Status: active"; then
    log "UFW is active; allowing 3389/tcp..."
    ufw allow 3389/tcp comment 'GNOME RDP' >/dev/null
    ok "Firewall rule added."
fi

# ---------- verify ----------
sleep 2
if ss -tlnp 2>/dev/null | grep -q ':3389\b'; then
    ok "GNOME RDP is listening on port 3389."
else
    warn "Service is running but nothing on port 3389 yet."
    warn "Check status: journalctl -u gnome-remote-desktop -n 50 --no-pager"
fi

cat <<EOF

${BOLD}Connect from your RDP client:${RESET}
  Host:     $(hostname -f 2>/dev/null || hostname):3389
  Username: ${RDP_USER}    ${YELLOW}(RDP-layer cred, not your Linux user)${RESET}
  Password: <the one you just set>

After the RDP handshake succeeds, GDM/GNOME will ask for your normal Linux
user credentials inside the session.
EOF
