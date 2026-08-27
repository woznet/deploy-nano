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

API_URL='https://api.github.com/repos/woznet/deploy-nano/contents/ubuntu/config/scripts?ref=main'
TARGET_DIR="$HOME/dev/scripts"

get_download_urls() {
    if command -v jq >/dev/null 2>&1; then
        curl -fsSL "$API_URL" | jq -r '.[].download_url | select(. != null)'
    else
        curl -fsSL "$API_URL" | grep -oP '"download_url":\s*"\K[^"]+'
    fi
}

main() {
    log "Downloading ubuntu/config/scripts (main) to $TARGET_DIR..."
    mkdir -p "$TARGET_DIR"

    local download_urls
    download_urls="$(get_download_urls)"

    if [ -z "$download_urls" ]; then
        warn "GitHub API returned no download URLs for $API_URL"
        exit 1
    fi

    local total=0 failed=0
    local url file
    while read -r url; do
        [ -n "$url" ] || continue
        file="$(basename "$url")"
        total=$((total+1))
        if curl -fsSL "$url" -o "$TARGET_DIR/$file"; then
            chmod +x "$TARGET_DIR/$file"
            log "Downloaded: $file"
        else
            failed=$((failed+1))
            warn "Failed to download: $file"
        fi
    done <<<"$download_urls"

    log "Done: $((total - failed))/$total scripts saved to $TARGET_DIR."
    [ "$failed" -eq 0 ] || exit 1
}

main
