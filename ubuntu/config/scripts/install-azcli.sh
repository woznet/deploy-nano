#!/usr/bin/env bash
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

AZ_REPO_URL='https://packages.microsoft.com/repos/azure-cli/'
AZ_SOURCE_FILE='/etc/apt/sources.list.d/azure-cli.sources'

# Microsoft publishes azure-cli for a subset of Ubuntu codenames only, and lags
# new releases by a long way: at the time of writing the newest suite in
# packages.microsoft.com/repos/azure-cli/dists/ is 'noble' (24.04) -- 25.04
# 'plucky', 25.10 'questing' and 26.04 'resolute' are all absent. Newest first;
# the first suite that is actually published wins.
AZ_FALLBACK_SUITES='noble jammy focal'

# /etc/os-release is present on every Ubuntu and Debian image; lsb_release is a
# package a minimal image may not carry, so it is the fallback and not the
# primary source.
host_codename() {
    local codename=''
    if [ -r /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
    fi
    if [ -z "$codename" ] && command -v lsb_release >/dev/null 2>&1; then
        codename="$(lsb_release -cs 2>/dev/null || true)"
    fi
    echo "$codename"
}

# A suite exists if and only if its Release index is fetchable. Checking before
# the source file is written is the point of the exercise: an unpublished suite
# breaks 'apt-get update' for every later script in the provisioning order, and
# the failure surfaces in one of those scripts rather than in this one.
suite_is_published() {
    curl -fs --head --max-time 15 -o /dev/null "${AZ_REPO_URL}dists/$1/Release"
}

# Prefer the host's own codename; otherwise degrade to the newest supported LTS
# that Microsoft actually publishes.
resolve_az_suite() {
    local detected="$1"
    local suite

    if [ -n "$detected" ] && suite_is_published "$detected"; then
        echo "$detected"
        return 0
    fi

    for suite in $AZ_FALLBACK_SUITES; do
        [ "$suite" = "$detected" ] && continue
        if suite_is_published "$suite"; then
            if [ -n "$detected" ]; then
                warn "Microsoft does not publish azure-cli for '$detected'; falling back to '$suite'."
            else
                warn "Could not determine the host codename; falling back to '$suite'."
            fi
            echo "$suite"
            return 0
        fi
    done

    return 1
}

if ! command -v az >/dev/null 2>&1; then
    sudo apt-get update -qq
    sudo apt-get install -qq -y apt-transport-https ca-certificates curl gnupg lsb-release

    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc |
        gpg --dearmor | sudo tee /etc/apt/keyrings/microsoft.gpg >/dev/null
    sudo chmod go+r /etc/apt/keyrings/microsoft.gpg

    AZ_DIST=$(host_codename)
    if ! AZ_SUITE=$(resolve_az_suite "$AZ_DIST"); then
        warn "No azure-cli suite is published for '${AZ_DIST:-unknown}' or for any"
        warn "supported fallback (${AZ_FALLBACK_SUITES// /, }); refusing to write"
        warn "$AZ_SOURCE_FILE. Azure CLI was not installed."
        exit 1
    fi

    log "Configuring the azure-cli apt repository (suite: ${AZ_SUITE})..."
    echo "Types: deb
URIs: ${AZ_REPO_URL}
Suites: ${AZ_SUITE}
Components: main
Architectures: $(dpkg --print-architecture)
Signed-by: /etc/apt/keyrings/microsoft.gpg" | sudo tee "$AZ_SOURCE_FILE" >/dev/null

    # A source that cannot be updated must not survive this script, or the next
    # install script fails on an 'apt-get update' it did not break.
    if ! sudo apt-get update -qq; then
        warn "apt-get update failed after adding $AZ_SOURCE_FILE; removing it."
        sudo rm -f "$AZ_SOURCE_FILE"
        exit 1
    fi

    sudo apt-get install -qq -y azure-cli

else
    log "Azure CLI already installed. Skipping."
fi
