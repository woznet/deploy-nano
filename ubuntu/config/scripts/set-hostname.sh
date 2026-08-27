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

usage() {
    echo "Usage: $(basename "$0") <hostname|fqdn>"
    echo
    echo "  Sets the system hostname and updates /etc/hosts."
    echo "  Pass a short hostname (mybox) or a full FQDN (mybox.example.com)."
    echo "  With an FQDN, the short name becomes the hostname and the FQDN is"
    echo "  recorded on the 127.0.1.1 line in /etc/hosts (Debian convention)."
}

validate_name() {
    local name="$1" label
    if [ "${#name}" -gt 253 ]; then
        warn "Name too long (max 253 characters): $name"
        exit 1
    fi
    IFS='.' read -ra labels <<<"$name"
    for label in "${labels[@]}"; do
        if [[ ! $label =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
            warn "Invalid hostname label: '$label' (letters, digits, and inner hyphens only, max 63 chars)"
            exit 1
        fi
    done
}

update_etc_hosts() {
    local hosts_entry="$1"
    if grep -q '^127\.0\.1\.1[[:space:]]' /etc/hosts; then
        sudo sed -i "s/^127\.0\.1\.1[[:space:]].*/127.0.1.1\t$hosts_entry/" /etc/hosts
    else
        printf '127.0.1.1\t%s\n' "$hosts_entry" | sudo tee -a /etc/hosts >/dev/null
    fi
}

main() {
    local name="$1" short_name fqdn hosts_entry old_hostname

    validate_name "$name"

    if [[ $name == *.* ]]; then
        fqdn="$name"
        short_name="${name%%.*}"
        hosts_entry="$fqdn $short_name"
    else
        fqdn=''
        short_name="$name"
        hosts_entry="$short_name"
    fi

    if ! command -v hostnamectl >/dev/null 2>&1; then
        warn 'hostnamectl not found; this script requires systemd (Ubuntu).'
        exit 1
    fi

    old_hostname="$(hostnamectl --static)"
    if [ "$old_hostname" = "$short_name" ]; then
        log "Hostname is already '$short_name'."
    else
        log "Setting hostname: $old_hostname -> $short_name"
        sudo hostnamectl set-hostname "$short_name"
    fi

    log "Updating /etc/hosts: 127.0.1.1 -> $hosts_entry"
    update_etc_hosts "$hosts_entry"

    if [ -n "$fqdn" ]; then
        log "Done. Hostname: $short_name, FQDN: $fqdn"
    else
        log "Done. Hostname: $short_name"
    fi
    log 'Open a new shell (or re-login) to see the new hostname in your prompt.'
}

case "${1:-}" in
    -h | --help)
        usage
        exit 0
        ;;
    '')
        usage
        exit 1
        ;;
esac

if [ $# -ne 1 ]; then
    warn 'Expected exactly one argument.'
    usage
    exit 1
fi

main "$1"
