#!/usr/bin/env bash
# ubuntu-update.sh: update an Ubuntu host (26.04 LTS)
set -euo pipefail

[[ $EUID -eq 0 ]] || {
        echo "Run as root." >&2
        exit 1
}

# Keep apt, debconf and needrestart from stopping to ask questions
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
apt_opts=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

echo "==> Refreshing package lists"
apt-get update

echo "==> Upgrading (full-upgrade)"
apt-get "${apt_opts[@]}" full-upgrade

echo "==> Cleaning up"
apt-get -y autoremove --purge
apt-get clean

if command -v snap >/dev/null 2>&1; then
        echo "==> Refreshing snaps"
        snap refresh
fi

# shellcheck source=/dev/null
. /etc/os-release
echo "==> $PRETTY_NAME"

running=$(uname -r)
latest=$(printf '%s\n' /boot/vmlinuz-* | sort -V | tail -n1)
latest=${latest#/boot/vmlinuz-}

if [[ -f /run/reboot-required ]]; then
        echo "==> Reboot needed (running kernel $running)"
        if [[ -f /run/reboot-required.pkgs ]]; then
                sort -u /run/reboot-required.pkgs | sed 's/^/    /'
        fi
elif [[ "$running" != "$latest" ]]; then
        echo "==> Reboot needed: running $running, newest installed $latest"
else
        echo "==> Reboot not required"
fi
