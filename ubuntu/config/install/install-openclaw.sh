#!/bin/bash
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

usage() {
    echo "Usage: $(basename "$0") [--skip-optional]"
    echo
    echo "  --skip-optional   Do not install the optional integrations"
    echo "                    (bun, tailscale, ripgrep, ffmpeg, jq)."
    echo
    echo "Environment:"
    echo "  OPENCLAW_SKIP_OPTIONAL=1   Same as --skip-optional."
    echo "  NODE_TARGET_MAJOR=26       Node.js major installed when the current one is unsupported."
}

SKIP_OPTIONAL="${OPENCLAW_SKIP_OPTIONAL:-0}"
NODE_TARGET_MAJOR="${NODE_TARGET_MAJOR:-26}"
RAW_BASE_URL='https://raw.githubusercontent.com/woznet/deploy-nano/main/ubuntu/config/install'
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-optional)
            SKIP_OPTIONAL=1
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            warn "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

# Run a sibling installer from this repo: prefer the local checkout, then the
# copy synced to ~/dev/scripts, then fall back to the raw GitHub source.
run_sibling() {
    local name="$1"
    shift

    if [ -f "$SCRIPT_DIR/$name" ]; then
        bash "$SCRIPT_DIR/$name" "$@"
    elif [ -f "$HOME/dev/scripts/$name" ]; then
        bash "$HOME/dev/scripts/$name" "$@"
    else
        log "$name not found locally; fetching from GitHub..."
        curl -fsSL "$RAW_BASE_URL/$name" | bash -s -- "$@"
    fi
}

sudo_cmd() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

apt_install() {
    log "Installing: $*"
    sudo_cmd env DEBIAN_FRONTEND=noninteractive apt-get update -qq
    sudo_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -qq -y "$@"
}

# Mirrors the OpenClaw installer's node_version_components_are_supported():
# 22 -> >= 22.22.3, 24 -> >= 24.15.0, 25 -> >= 25.9.0, > 25 -> supported.
node_version_is_supported() {
    local version major minor patch
    version="$(node -p 'process.versions.node' 2>/dev/null || echo '')"
    [ -n "$version" ] || return 1

    IFS='.' read -r major minor patch <<<"$version"
    case "$major" in
        22) [ "$minor" -gt 22 ] || { [ "$minor" -eq 22 ] && [ "$patch" -ge 3 ]; } ;;
        24) [ "$minor" -gt 15 ] || { [ "$minor" -eq 15 ] && [ "$patch" -ge 0 ]; } ;;
        25) [ "$minor" -gt 9 ] || { [ "$minor" -eq 9 ] && [ "$patch" -ge 0 ]; } ;;
        *) [ "$major" -gt 25 ] ;;
    esac
}

# Mirrors the OpenClaw installer's node_binary_has_safe_sqlite(): OpenClaw state
# is stored through node:sqlite, so a Node without it is rejected at startup.
node_has_safe_sqlite() {
    node -e 'const { DatabaseSync } = require("node:sqlite"); new DatabaseSync(":memory:").close();' >/dev/null 2>&1
}

node_is_ready() {
    command -v node >/dev/null 2>&1 && node_version_is_supported && node_has_safe_sqlite
}

# install-node.sh only exports PATH inside its own process, so pick up the npm
# global prefix it configures in ~/.bashrc.
rehydrate_path() {
    local npm_bin="$HOME/.npm-global/bin"

    if command -v npm >/dev/null 2>&1; then
        npm_bin="$(npm prefix -g 2>/dev/null)/bin"
    fi

    case ":$PATH:" in
        *":$npm_bin:"*) ;;
        *) export PATH="$npm_bin:$PATH" ;;
    esac
    hash -r
}

check_hard_requirements() {
    log "Checking hard requirements..."

    if [ "$(uname -s)" != "Linux" ] || ! command -v apt-get >/dev/null 2>&1; then
        warn "This script targets Debian/Ubuntu Linux (apt-get not found)."
        exit 1
    fi

    if [ "$(id -u)" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
        warn "sudo is required for system installs on Linux. Install sudo or re-run as root."
        exit 1
    fi

    local missing=()
    local pkg
    for pkg in curl tar git; do
        command -v "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        apt_install "${missing[@]}" ca-certificates
    fi
    for pkg in curl tar git; do
        log "  $pkg  -> $(command -v "$pkg") OK"
    done

    if node_is_ready; then
        log "  node  -> v$(node -p 'process.versions.node') OK"
    else
        if command -v node >/dev/null 2>&1; then
            log "  node  -> $(node -p 'process.versions.node' 2>/dev/null || echo 'unknown') (needs 22.22.3+, 24.15.0+, or 25.9.0+ with node:sqlite)"
        else
            log "  node  -> not installed (needs 22.22.3+, 24.15.0+, or 25.9.0+)"
        fi

        log "Installing Node ${NODE_TARGET_MAJOR} via install-node.sh..."
        run_sibling install-node.sh "$NODE_TARGET_MAJOR"
        rehydrate_path

        if ! node_is_ready; then
            warn "Node.js is still unsupported after installing ${NODE_TARGET_MAJOR}.x: $(node -p 'process.versions.node' 2>/dev/null || echo 'not found')"
            warn "OpenClaw requires Node 22.22.3+, 24.15.0+, or 25.9.0+ with a working node:sqlite."
            exit 1
        fi
        log "  node  -> v$(node -p 'process.versions.node') OK"
    fi

    rehydrate_path
    if ! command -v npm >/dev/null 2>&1; then
        warn "npm not found; OpenClaw installs through 'npm install -g openclaw@latest'."
        exit 1
    fi
    log "  npm   -> $(npm --version) OK"
}

install_optional() {
    if [ "$SKIP_OPTIONAL" = "1" ]; then
        log "Skipping optional integrations (--skip-optional): bun, tailscale, ripgrep, ffmpeg, jq."
        return 0
    fi

    log "Checking optional integrations..."

    if command -v bun >/dev/null 2>&1; then
        log "  bun        present"
    else
        log "  bun        missing - installing via install-bun.sh..."
        if ! run_sibling install-bun.sh; then
            warn "Failed to install bun; continuing without it."
        fi
    fi

    if command -v tailscale >/dev/null 2>&1; then
        log "  tailscale  present"
    else
        log "  tailscale  missing - installing via install-tailscale.sh..."
        if ! run_sibling install-tailscale.sh; then
            warn "Failed to install tailscale; continuing without it."
        fi
    fi

    local apt_missing=()
    command -v rg >/dev/null 2>&1 || apt_missing+=("ripgrep")
    command -v ffmpeg >/dev/null 2>&1 || apt_missing+=("ffmpeg")
    command -v jq >/dev/null 2>&1 || apt_missing+=("jq")

    if [ ${#apt_missing[@]} -gt 0 ]; then
        if ! apt_install "${apt_missing[@]}"; then
            warn "Failed to install: ${apt_missing[*]}; continuing without them."
        fi
    fi

    hash -r
    log "Optional integrations:"
    local entry name cmd
    for entry in "bun:bun" "tailscale:tailscale" "ripgrep:rg" "ffmpeg:ffmpeg" "jq:jq"; do
        name="${entry%%:*}"
        cmd="${entry##*:}"
        if command -v "$cmd" >/dev/null 2>&1; then
            log "  $name  present"
        else
            log "  $name  MISSING"
        fi
    done
}

main() {
    log "Starting OpenClaw installation..."

    check_hard_requirements
    install_optional

    log "Running the OpenClaw installer..."
    curl -fsSL https://openclaw.ai/install.sh | bash

    rehydrate_path
    log "OpenClaw $(openclaw --version 2>/dev/null || echo 'installed') installed successfully."
    log "Run 'openclaw onboard' to configure this machine."
}

# The guard below runs before anything hydrates PATH, so pick up the npm
# global prefix first - otherwise an installed openclaw is missed and
# reinstalled on every run.
rehydrate_path
if command -v openclaw >/dev/null 2>&1; then
    log "OpenClaw is already installed. Skipping."
else
    main
fi
