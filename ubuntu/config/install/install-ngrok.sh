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

# Run a command as the invoking operator while we are root. When we already are
# that operator, run it directly -- sudo would only add a needless password
# prompt to a write into the user's own home.
run_as() {
    local user="$1"
    shift
    if [ "$(id -u)" -eq 0 ]; then
        sudo -u "$user" -H -- "$@"
    else
        "$@"
    fi
}

# Under 'sudo ./install-ngrok.sh', $HOME is /root, so completions written there
# are completions the operator who ran the script never sees. Resolve the
# invoking user the way install-docker.sh:96 does and write into *their* home,
# or skip with a warning when there is no such user.
install_completions() {
    local target_user target_home comp_dir

    # The top-level guard ran 'command -v ngrok' before the install, so bash may
    # still be holding the negative lookup from it; drop that before asking
    # again. The old code assumed ngrok was on PATH here and never checked.
    hash -r
    if ! command -v ngrok >/dev/null 2>&1; then
        warn "ngrok is not on PATH after installation; skipping Bash completions."
        return 0
    fi

    if [ "$(id -u)" -eq 0 ]; then
        target_user="${SUDO_USER:-root}"
    else
        target_user="$(id -un)"
    fi
    if [ "$target_user" = "root" ]; then
        warn "Invoking user resolved to 'root'; skipping Bash completions."
        warn "Run this as your own user to get them:"
        warn "  ngrok completion bash > ~/.local/share/bash-completion/completions/ngrok"
        return 0
    fi

    target_home="$(getent passwd "$target_user" | cut -d: -f6 || true)"
    if [ -z "$target_home" ] || [ ! -d "$target_home" ]; then
        warn "No usable home directory for '$target_user'; skipping Bash completions."
        return 0
    fi

    comp_dir="$target_home/.local/share/bash-completion/completions"
    log "Installing Bash completions for $target_user into $comp_dir..."
    run_as "$target_user" mkdir -p "$comp_dir"
    ngrok completion bash | run_as "$target_user" tee "$comp_dir/ngrok" >/dev/null
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

    # 'bookworm' is a Debian suite and is deliberately NOT derived from the
    # host's codename. ngrok publishes one apt repository for every Debian and
    # Ubuntu host, and its bucket carries Debian suites only -- dists/ holds
    # bookworm, bullseye and buster and nothing else; there has never been a
    # noble/jammy/focal there. bookworm is the newest of the three, and the
    # package itself is a release-independent static binary. Do not template
    # this from /etc/os-release: every Ubuntu codename 404s.
    echo "deb [signed-by=/etc/apt/keyrings/ngrok.asc] https://ngrok-agent.s3.amazonaws.com bookworm main" |
        sudo tee /etc/apt/sources.list.d/ngrok.list >/dev/null

    log "Updating apt and installing Ngrok..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -qq -y ngrok

    install_completions

    log "Ngrok installed successfully."
}
if ! command -v ngrok >/dev/null 2>&1; then
    main
else
    log "Ngrok is already installed. Skipping."
fi
