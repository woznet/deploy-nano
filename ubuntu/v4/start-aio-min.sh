#!/bin/bash
set -e
set -o pipefail

ORANGE_RED='\033[38;2;255;69;0m'
NC='\033[0m'

# Configuration variables shared across all scripts
PWSH_PROFILE_URL='https://raw.githubusercontent.com/woznet/deploy-nano/main/ubuntu/config/profile.ps1'
PWSH_CONFIG_URL='https://raw.githubusercontent.com/woznet/deploy-nano/main/ubuntu/config/Invoke-ConfigPwsh.ps1'
BASHRC_URL='https://raw.githubusercontent.com/woznet/deploy-nano/main/ubuntu/config/.bashrc'
BASH_ALIASES_URL='https://raw.githubusercontent.com/woznet/deploy-nano/main/ubuntu/config/.bash_aliases'
SUDOERS_URL='https://raw.githubusercontent.com/woznet/deploy-nano/main/ubuntu/config/sudoers.woz'
INPUTRC_URL='https://raw.githubusercontent.com/woznet/deploy-nano/main/ubuntu/config/inputrc'
NANORC_URL='https://raw.githubusercontent.com/woznet/deploy-nano/main/ubuntu/config/nanorc'
# DISABLE_IPV6_URL='https://raw.githubusercontent.com/woznet/deploy-nano/main/ubuntu/config/20-disable-ipv6.conf'

NANO_SYNTAX_TEMP_PATH='/tmp/nanosyntaxpath.tmp'
NANO_BUILD_TEMP_PATH='/tmp/nanobuildpath.tmp'

NANO_SYNTAX_REPO='https://github.com/galenguyer/nano-syntax-highlighting.git'

export DEBIAN_FRONTEND=noninteractive

# Define the functions that will be used in the script
check_dependency() {
    command -v "$1" >/dev/null 2>&1 || {
        echo -e "${ORANGE_RED}Error: Required command '$1' not found.${NC}\n" >&2
        exit 1
    }
}

setup_completions() {
    echo "Deploying shell completions..."

    # Define variables locally to prevent global scope leakage
    local target_dir timestamp error_log error_msg
    target_dir="$HOME/.local/share/bash-completion/completions"
    timestamp=$(date +'%Y%m%d_%H%M%S')
    error_log="error_log_${timestamp}.txt"
    error_msg=""

    # 1. Proactively create the target directory
    mkdir -p "$target_dir"

    # Table for command-based completions
    local -A command_completions=(
        [op]='op completion bash'
        [pip]='pip completion --bash'
        [npm]='npm completion bash'
        [rclone]='rclone completion bash'
        [ngrok]='ngrok completion bash'
        [gh]='gh completion --shell bash'
        [dotnet]='dotnet completions script bash'
    )

    # Table for URL-based completions
    local -A url_completions=(
        [tldr]='https://raw.githubusercontent.com/tldr-pages/tldr-node-client/main/bin/completion/bash/tldr'
        [clang]='https://raw.githubusercontent.com/llvm-mirror/clang/master/utils/bash-autocomplete.sh'
        [az]='https://raw.githubusercontent.com/Azure/azure-cli/dev/az.completion'
    )

    # ---------------------------------------------------------
    # Process Command-based Completions
    # ---------------------------------------------------------
    for key in "${!command_completions[@]}"; do
        local value output_file
        value="${command_completions[$key]}"
        output_file="${target_dir}/${key}" # Removed _completion suffix

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Generating command completion for key: $key" | tee -a "$error_log"

        # Ensure the command exists before generating
        local command_name
        command_name=$(echo "$value" | awk '{print $1}')
        if ! command -v "$command_name" &>/dev/null; then
            error_msg="[$key] Command '$command_name' not found. Skipping."
            echo -e "${ORANGE_RED}${error_msg}${NC}"
            echo "[$(date)] $error_msg" >>"$error_log"
            continue
        fi

        # Generate output directly into the file (No sudo or tee needed)
        if eval "$value" >"$output_file" 2>>"$error_log"; then
            chmod 644 "$output_file"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Successfully generated $key completion. Saved to $output_file." | tee -a "$error_log"
        else
            error_msg="[$key] Failed to generate output for '$value'. Skipping."
            echo -e "${ORANGE_RED}${error_msg}${NC}"
            echo "[$(date)] $error_msg" >>"$error_log"
        fi
    done

    # ---------------------------------------------------------
    # Process URL-based Completions
    # ---------------------------------------------------------
    for key in "${!url_completions[@]}"; do
        local value output_file
        value="${url_completions[$key]}"
        output_file="${target_dir}/${key}" # Removed _completion suffix

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Downloading URL completion for key: $key from $value" | tee -a "$error_log"

        # Download directly (No sudo needed)
        if ! curl -fsSL "$value" -o "$output_file"; then
            error_msg="[$key] Failed to download completion script from $value"
            echo -e "${ORANGE_RED}${error_msg}${NC}"
            echo "[$(date)] $error_msg" >>"$error_log"
            continue
        fi

        if ! chmod 644 "$output_file"; then
            error_msg="[$key] Failed to set permissions on $output_file."
            echo -e "${ORANGE_RED}${error_msg}${NC}"
            echo "[$(date)] $error_msg" >>"$error_log"
            continue
        fi

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Successfully downloaded $key completion. Saved to $output_file." | tee -a "$error_log"
    done

    echo "All completion scripts have been processed."
}

error_handler() {
    local exit_status=$?
    local line_no=$1
    echo -e "${ORANGE_RED}An error occurred at or near line ${line_no}. Exit status: ${exit_status}${NC}\n"
    log_error "Error occurred at or near line ${line_no}. Exit status: ${exit_status}"
    exit $exit_status
}

log() {
    local message="$1"
    local level="${2:-INFO}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOGFILE"
}

log_error() {
    log "$1" "ERROR"
}

error_exit() {
    echo -e "${ORANGE_RED}Error occurred. Exiting.${NC}\n"
    log_error 'Error occurred. Exiting.'
    exit 1
}

run_command() {
    export DEBIAN_FRONTEND=noninteractive
    if [[ $# -eq 1 ]]; then
        local cmd="$1"
        log "Running command (string): $cmd"
        eval "$cmd" || {
            log_error "Command failed: $cmd"
            error_exit
        }
    else
        log "Running command (args): $*"
        "$@" || {
            log_error "Command failed: $*"
            error_exit
        }
    fi
}

download_file() {
    local url="$1"
    local dest="$2"
    log "Downloading $url to $dest"
    # Determine if sudo is needed (check write permission)
    if [[ ! -w "$(dirname "$dest")" ]]; then
        use_sudo="sudo"
    else
        use_sudo=""
    fi
    # Download file and handle errors
    if ! curl -fsSL "$url" | $use_sudo tee "$dest" >/dev/null; then
        echo -e "${ORANGE_RED}Failed to download $url to $dest${NC}\n"
        log_error "Failed to download $url"
        error_exit
    fi
    # Set permissions
    if ! $use_sudo chmod 644 "$dest"; then
        echo -e "${ORANGE_RED}Failed to set permissions for $dest${NC}\n"
        log_error "Failed to set permissions for $dest"
        error_exit
    fi
    # Check if file is empty
    if [ ! -s "$dest" ]; then
        echo -e "${ORANGE_RED}Downloaded file $dest is empty.${NC}\n"
        log_error "Downloaded file $dest is empty."
        error_exit
    fi
    log "Downloaded $url to $dest successfully."
}

source_external_script() {
    local tmp_file url
    url="$1"
    tmp_file="/tmp/temp_script.sh"

    if ! curl -fsSL "$url" -o "$tmp_file"; then
        echo -e "${ORANGE_RED}Failed to download script from $url${NC}\n"
        log_error "Failed to download script from $url"
        exit 1
    fi

    if [ ! -s "$tmp_file" ]; then
        echo -e "${ORANGE_RED}Downloaded script from $url is empty.${NC}\n"
        log_error "Downloaded script from $url is empty."
        rm -f "$tmp_file"
        exit 1
    fi

    # shellcheck source=/dev/null
    source "$tmp_file"

    rm -f "$tmp_file"
}

# Load functions
set_timezone() {
    log 'Setting timezone to America/New_York'
    run_command 'sudo timedatectl set-timezone America/New_York'
}

check_updates() {
    log 'Starting software update...'
    run_command 'sudo DEBIAN_FRONTEND=noninteractive apt update -qq > /dev/null'
    log 'Software update completed successfully.'
}

install_updates() {
    log 'Starting full upgrade...'
    run_command 'sudo DEBIAN_FRONTEND=noninteractive apt full-upgrade -qq -y > /dev/null'
    log 'Full upgrade completed successfully.'
}

install_software() {
    log 'Starting installation of required software packages...'

    source /etc/os-release

    # Packages common to Ubuntu and Kali
    local common_pkgs="apt-transport-https aptitude aptitude-doc-en curl \
software-properties-common git autopoint build-essential devhelp freetype2-doc \
g++-multilib gcc-multilib wget xdg-utils glibc-doc glibc-doc-reference \
glibc-source groff groff-base clang libasprintf-dev libbsd-dev libc++-dev \
libc6 libc6-dev libcairo2-dev libcairo2-doc libc-ares-dev python3-pip libc-dev \
libev-dev libgettextpo-dev libgirepository1.0-dev libglib2.0-doc libice-doc \
libmagic1 ca-certificates libmagic-dev libmagick++-dev libmagics++-dev \
libncurses-dev python-is-python3 libsm-doc libx11-doc libxcb-doc libxext-doc \
libxml2-utils ncurses-doc pkg-config zlib1g-dev net-tools gpg ffmpeg ffmpeg-doc \
most openssh-client openssh-known-hosts python3 python3-doc p7zip p7zip-full \
policykit-1-doc rclone unzip zip unrar-free jq ripgrep fzf \
bat fd-find tree htop btop lsof rsync dnsutils mtr-tiny tmux aspell aspell-en \
autoconf automake libtool ssh-import-id xorg xrdp xorgxrdp"

    # Distro-specific extras
    local distro_pkgs=""
    if [[ "$ID" == "kali" ]]; then
        # Kali: 'locales' for manual locale generation below.
        # Ubuntu drops: language-pack-* (Canonical-only), libncurses5-dev /
        # libncursesw5-dev (removed in Debian trixie+), policykit-desktop-privileges (Canonical-only).
        distro_pkgs="locales"
    else
        # Ubuntu (and Ubuntu-derived distros).
        distro_pkgs="language-pack-en language-pack-en-base libncurses5-dev libncursesw5-dev policykit-desktop-privileges policykit-1-gnome"
    fi

    run_command "sudo DEBIAN_FRONTEND=noninteractive apt install -qq -y $common_pkgs $distro_pkgs > /dev/null"

    # Kali-only: language-pack equivalent. Ubuntu handles this automatically
    # via the language-pack-* package triggers, so it's a no-op there.
    if [[ "$ID" == "kali" ]]; then
        log 'Configuring locales for Kali...'
        run_command 'echo "locales locales/default_environment_locale select en_US.UTF-8" | sudo debconf-set-selections'
        run_command 'echo "locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8" | sudo debconf-set-selections'
        run_command 'sudo rm -f /etc/default/locale'
        run_command 'sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure locales'
    fi

    log 'Software installation completed successfully.'
}

configure_userenv() {
    log 'Starting user environment configuration setup...'

    generate_ssh_keys

    # Set clock to 12-hour format - branch by desktop environment.
    # Note: these commands write to the *current user's* config, so they
    # need a running session bus. If you run this script via SSH before
    # ever logging into the desktop, they may fail silently; re-run after
    # first Xfce/GNOME login if needed.
    if command -v xfconf-query &>/dev/null; then
        # Xfce (Kali default). --create ensures the property exists if it
        # hasn't been written to yet; -t string sets its type.
        if xfconf-query -c xfce4-panel -p /plugins/clock/digital-format -s '%I:%M:%S %p' --create -t string 2>/dev/null; then
            log 'Xfce clock format set to 12-hour.'
        else
            echo -e "${ORANGE_RED}Warning: Failed to set Xfce clock format (likely needs manual panel config on first Xfce login).${NC}\n"
            log_error 'Failed to set Xfce clock format via xfconf-query.'
        fi
    elif command -v gsettings &>/dev/null; then
        # GNOME (Ubuntu default).
        if gsettings set org.gnome.desktop.interface clock-format 12h 2>/dev/null; then
            log 'GNOME clock format set to 12-hour.'
        else
            echo -e "${ORANGE_RED}Warning: Failed to set GNOME clock format.${NC}\n"
            log_error 'Failed to set GNOME clock format via gsettings.'
        fi
    else
        echo -e "${ORANGE_RED}Warning: Neither xfconf-query nor gsettings found. Skipping clock format configuration.${NC}\n"
        log_error 'Neither xfconf-query nor gsettings found. Skipping clock format configuration.'
    fi

    log 'Configuring .bashrc and .bash_aliases...'
    download_file "$BASHRC_URL" "$HOME/.bashrc"
    download_file "$BASH_ALIASES_URL" "$HOME/.bash_aliases"

    # BUGFIX: Changed ~ to $HOME and wrapped in double quotes for safe variable expansion
    run_command "sudo cp --force $HOME/.bashrc /root/.bashrc"
    run_command "sudo ln --force $HOME/.bash_aliases /root/.bash_aliases"

    log 'Configuring sudoers, inputrc and needrestart.conf...'
    download_file "$SUDOERS_URL" '/etc/sudoers.d/woz'
    download_file "$INPUTRC_URL" '/etc/inputrc'
    # download_file "$DISABLE_IPV6_URL" '/etc/sysctl.d/20-disable-ipv6.conf'

    if [[ -f "/etc/needrestart/needrestart.conf" ]]; then
        # BUGFIX: Wrapped the entire command in double quotes for run_command.
        # Escaped the $ signs (\$) so ShellCheck is happy and Bash ignores the Perl variables.
        run_command "sudo sed -i.bak -e 's/^#[[:space:]]*\$nrconf{verbosity}[[:space:]]*=[[:space:]]*2;\$/\$nrconf{verbosity} = 0;/' /etc/needrestart/needrestart.conf"
    fi

    log 'Creating user directories...'
    for dir in "$HOME/git" "$HOME/temp" "$HOME/dev"; do
        # Added -p to mkdir so it doesn't error out if the directory already exists
        [ -d "$dir" ] || run_command "mkdir -p '$dir'"
    done

    log 'User environment configuration setup completed successfully.'
}

remove_rhythmbox() {
    source /etc/os-release
    if [[ "$ID" == "kali" ]]; then
        log 'Skipping Rhythmbox/Aisleriot purge - not applicable on Kali.'
        return 0
    fi

    log 'Starting removal of Rhythmbox and Aisleriot...'
    run_command 'sudo DEBIAN_FRONTEND=noninteractive apt purge -qq -y rhythmbox* aisleriot > /dev/null'
    log 'Rhythmbox and Aisleriot removal completed successfully.'
}

generate_ssh_keys() {
    log 'Checking for existing SSH keys...'

    if [ ! -f "$HOME/.ssh/id_rsa" ]; then
        log "Creating SSH key at $HOME/.ssh/id_rsa"

        # BUGFIX: Wrapped in double quotes so $(id) and $(hostname) actually execute.
        # Swapped ~ to $HOME for reliable path resolution.
        run_command "ssh-keygen -t rsa -b 4096 -C \"$(id --name --user)@$(hostname --fqdn)\" -N '' -f \"$HOME/.ssh/id_rsa\""

        log 'SSH key generated successfully.'
    else
        # echo -e "${ORANGE_RED}Warning: SSH key already exists. Skipping key generation.${NC}\n"
        log 'SSH key already exists.'
    fi
}

import_github_ssh_keys() {
    local gh_user="${GITHUB_SSH_USER:-woznet}"
    log "Importing SSH keys from GitHub user: $gh_user"

    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    if command -v ssh-import-id &>/dev/null; then
        run_command "ssh-import-id gh:$gh_user"
    else
        # Fallback: direct fetch, with dedup against existing keys
        local tmp_keys
        tmp_keys=$(mktemp)
        if curl -fsSL "https://github.com/$gh_user.keys" -o "$tmp_keys"; then
            touch "$HOME/.ssh/authorized_keys"
            # Append only keys not already present
            while IFS= read -r key; do
                [[ -z "$key" ]] && continue
                grep -qxF "$key" "$HOME/.ssh/authorized_keys" || echo "$key" >> "$HOME/.ssh/authorized_keys"
            done < "$tmp_keys"
            rm -f "$tmp_keys"
            chmod 600 "$HOME/.ssh/authorized_keys"
            log "GitHub SSH keys imported successfully."
        else
            log_error "Failed to fetch GitHub keys for $gh_user"
            rm -f "$tmp_keys"
            return 1
        fi
    fi
}

configure_sshd() {
    log 'Configuring SSH server for pubkey-only authentication...'

    # Install openssh-server if not present (Kali ships it but the service is
    # disabled by default; some minimal installs may not have the package at all)
    if ! dpkg -s openssh-server &>/dev/null; then
        log 'Installing openssh-server...'
        run_command 'sudo DEBIAN_FRONTEND=noninteractive apt install -qq -y openssh-server > /dev/null'
    fi

    # SAFETY: refuse to disable password auth if no authorized_keys exists.
    # This is the difference between a hardened box and a locked-out box.
    if [[ ! -s "$HOME/.ssh/authorized_keys" ]]; then
        echo -e "${ORANGE_RED}Refusing to disable password auth: $HOME/.ssh/authorized_keys is missing or empty.${NC}\n"
        log_error 'Skipping SSH hardening: no authorized_keys present.'
        return 1
    fi

    # Drop-in config rather than editing /etc/ssh/sshd_config directly.
    # Modern OpenSSH on Debian/Kali Includes /etc/ssh/sshd_config.d/*.conf,
    # so this survives package upgrades cleanly and is easy to revert.
    local sshd_drop_in='/etc/ssh/sshd_config.d/99-pubkey-only.conf'
    log "Writing SSH hardening drop-in to $sshd_drop_in..."

    sudo tee "$sshd_drop_in" > /dev/null <<'EOF'
# Pubkey-only SSH authentication
# Managed by deploy script - edits will be overwritten on re-run

PasswordAuthentication no
PubkeyAuthentication yes
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no

# Default for PermitRootLogin is 'prohibit-password' which already blocks
# password root logins. Uncomment to disable key-based root login too:
# PermitRootLogin no
EOF

    sudo chmod 644 "$sshd_drop_in"

    # Validate config before touching the running service
    if ! sudo sshd -t; then
        echo -e "${ORANGE_RED}Error: sshd config test failed. Not restarting service.${NC}\n"
        log_error 'sshd -t failed; refusing to restart ssh service.'
        return 1
    fi

    # Verify the drop-in actually took effect (catches the rare case where
    # the Include directive is missing from the main sshd_config)
    if ! sudo sshd -T | grep -qx 'passwordauthentication no'; then
        echo -e "${ORANGE_RED}Warning: effective sshd config still allows password auth. Drop-in may not be loading - check 'Include /etc/ssh/sshd_config.d/*.conf' in /etc/ssh/sshd_config.${NC}\n"
        log_error 'Effective sshd config did not apply pubkey-only settings.'
        return 1
    fi

    run_command 'sudo systemctl enable ssh'
    run_command 'sudo systemctl restart ssh'

    log 'SSH server configured for pubkey-only auth.'
}

install_gh() {
    log 'Starting installation of GitHub CLI...'

    # BUGFIX: Test the exit code directly, no subshell or brackets needed
    if ! command -v gh &>/dev/null; then
        run_command 'curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg'
        run_command 'sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg'

        # BUGFIX: Outer double quotes so $(dpkg ...) expands. Escaped inner double quotes. Added >/dev/null for silence.
        run_command "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null"

        run_command 'sudo DEBIAN_FRONTEND=noninteractive apt update -qq > /dev/null'
        run_command 'sudo DEBIAN_FRONTEND=noninteractive apt install -qq -y gh > /dev/null'

        log 'GitHub CLI installation completed successfully.'
    else
        echo -e "${ORANGE_RED}Warning: GitHub CLI is already installed. Skipping installation.${NC}\n"
        log 'GitHub CLI is already installed.'
    fi
}

install_pwsh() {
    log 'Starting installation of PowerShell...'

    # If pwsh is installed, only proceed when GitHub has a newer stable release
    if command -v pwsh &>/dev/null; then
        local installed_version latest_version
        installed_version=$(pwsh --version 2>/dev/null | awk '{print $NF}')
        log "Installed PowerShell version: $installed_version"

        # Fetch latest stable release tag from GitHub (strips the leading 'v').
        # /releases/latest excludes prereleases and drafts, so this is always a stable build.
        latest_version=$(curl -fsSL https://api.github.com/repos/PowerShell/PowerShell/releases/latest 2>/dev/null \
            | jq -r '.tag_name' \
            | sed 's/^v//')

        if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
            echo -e "${ORANGE_RED}Warning: Could not determine latest PowerShell version from GitHub. Skipping update check.${NC}\n"
            log_error 'Could not determine latest PowerShell version. Skipping update check.'
            return 0
        fi

        log "Latest PowerShell version available: $latest_version"

        if [[ "$installed_version" == "$latest_version" ]]; then
            log 'PowerShell is up-to-date. Skipping installation.'
            return 0
        fi

        # If installed_version does NOT sort first in -V order, it's >= latest, so skip.
        # This handles the case where installed is a newer preview/dev build.
        if [[ "$(printf '%s\n%s' "$installed_version" "$latest_version" | sort -V | head -n1)" != "$installed_version" ]]; then
            log "Installed PowerShell ($installed_version) is newer than latest stable ($latest_version). Skipping installation."
            return 0
        fi

        log "PowerShell upgrade available: $installed_version -> $latest_version. Proceeding with install."
    else
        log 'PowerShell not installed. Proceeding with fresh installation.'
    fi

    # Install or upgrade
    source /etc/os-release

    if [[ "$ID" == "kali" ]]; then
        # PowerShell ships in Kali's main repo - no Microsoft repo needed
        log 'Installing PowerShell from Kali repos...'
        run_command 'sudo DEBIAN_FRONTEND=noninteractive apt install -qq -y powershell > /dev/null'
    else
        # Ubuntu/Debian path - use Microsoft's repo
        run_command 'sudo apt update -qq > /dev/null'
        run_command "wget -q \"https://packages.microsoft.com/config/$ID/$VERSION_ID/packages-microsoft-prod.deb\""
        run_command 'sudo dpkg -i packages-microsoft-prod.deb > /dev/null'
        run_command 'sudo DEBIAN_FRONTEND=noninteractive apt update -qq > /dev/null'
        run_command 'rm -f packages-microsoft-prod.deb > /dev/null'
        run_command 'sudo DEBIAN_FRONTEND=noninteractive apt install -qq -y powershell > /dev/null'
    fi

    run_command "sudo pwsh -NoProfile -Command \"Invoke-Expression ([System.Net.WebClient]::new().DownloadString('$PWSH_CONFIG_URL'))\" > /dev/null"
    download_file "$PWSH_PROFILE_URL" '/opt/microsoft/powershell/7/profile.ps1'
    log 'PowerShell installation completed successfully.'
}

install_1password() {

    log "Starting 1Password and 1Password CLI installation..."
    if ! command -v 1password &>/dev/null || ! command -v op &>/dev/null; then
        # 1. Add the GPG key
        log "Adding 1Password GPG key..."
        # Using --yes to prevent gpg from hanging if the key already exists
        curl -sS https://downloads.1password.com/linux/keys/1password.asc |
            sudo gpg --yes --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg

        # 2. Add the apt repository
        log "Configuring the 1Password apt repository..."
        local arch
        arch=$(dpkg --print-architecture)

        # We use double quotes here so the $arch variable expands correctly
        echo "deb [arch=$arch signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$arch stable main" |
            sudo tee /etc/apt/sources.list.d/1password.list >/dev/null

        # 3. Configure debsig-verify policy
        # 1Password uses this to verify the digital signatures of their .deb packages
        log "Configuring debsig-verify policies for package security..."
        sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22/

        curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol |
            sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol >/dev/null

        sudo mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22

        curl -sS https://downloads.1password.com/linux/keys/1password.asc |
            sudo gpg --yes --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg

        # 4. Install both packages
        log "Updating apt and installing 1Password and CLI..."
        sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -qq -y 1password 1password-cli

        log "1Password and 1Password CLI installed successfully!"
    else
        echo -e "${ORANGE_RED}Warning: 1Password and 1Password CLI are already installed. Skipping installation.${NC}\n"
        log '1Password and 1Password CLI are already installed.'
    fi
}

remove_nano() {
    log 'Checking if nano is installed...'
    if [[ $(command -v nano) ]]; then
        log 'Nano is installed. Removing nano...'
        run_command 'sudo DEBIAN_FRONTEND=noninteractive apt purge -qq -y nano > /dev/null'
        log 'Nano removed successfully.'
    else
        echo -e "${ORANGE_RED}Warning: Nano is not installed. Skipping removal.${NC}\n"
        log 'Nano is not installed.'
    fi
}

clone_nano_syntax() {
    log 'Cloning nano syntax highlighting repository...'
    run_command "sudo rm --recursive --force \"$HOME/git/nano-syntax-highlighting\" > /dev/null"
    run_command "git clone \"$NANO_SYNTAX_REPO\" \"$HOME/git/nano-syntax-highlighting\" > /dev/null"
    readlink -f "$HOME/git/nano-syntax-highlighting" >"$NANO_SYNTAX_TEMP_PATH"
    log 'Cloned nano syntax highlighting repository successfully.'
}

get_installed_nano_version() {
    log "Fetching installed nano version" >/dev/null
    if [[ $(command -v nano) ]]; then
        local installed_nano_version
        installed_nano_version=$(nano --version | head -n1 | awk '{print $4}')
        log "Installed nano version is $installed_nano_version" >/dev/null
        echo "$installed_nano_version"
    else
        log "Nano is not installed, returning version 0.0" >/dev/null
        echo "0.0"
    fi
}

get_latest_nano_version() {
    if [[ -n "$NANO_VERSION" ]]; then
        log "Using NANO_VERSION environment variable: $NANO_VERSION" >/dev/null
        echo "$NANO_VERSION"
        return
    fi

    log "Fetching latest nano version" >/dev/null
    local nano_version
    nano_version=$(git ls-remote --sort=-'version:refname' --tags https://git.savannah.gnu.org/git/nano.git 2>/dev/null |
        head -n1 |
        awk '{print $2}' |
        sed -E "s/^refs\/tags\/v//; s/\^\{\}$//")

    if [[ -z "$nano_version" ]]; then
        nano_version="8.7"
        log "Git command failed, falling back to version $nano_version" >/dev/null
    fi

    log "Latest nano version is $nano_version" >/dev/null
    echo "$nano_version"
}

download_nano() {
    log 'Downloading nano source...'

    # Safely change directory, or exit if it fails
    cd "$HOME/temp" || {
        log_error "Failed to cd to $HOME/temp"
        exit 1
    }

    run_command 'sudo rm --recursive --force ./nano-* > /dev/null'

    # Using double quotes on the outside so variables expand properly
    run_command "wget -q '${NANO_SOURCE_URL}'"
    run_command "tar xfz 'nano-${NANO_LATEST_VERSION}.tar.gz' > /dev/null"

    # Command substitution properly quoted
    readlink -f "$(printf 'nano-%s' "$NANO_LATEST_VERSION")" >"$NANO_BUILD_TEMP_PATH"

    log 'Downloaded and extracted nano source successfully.'
}

build_nano() {
    log 'Configuring and building nano...'

    # 1. Safely enter the directory
    local build_dir
    build_dir=$(cat "$NANO_BUILD_TEMP_PATH")
    cd "$build_dir" || {
        log "Failed to enter build directory: $build_dir"
        exit 1
    }

    # 2. Configure and Make WITHOUT sudo.
    # Added --enable-libmagic to utilize the libmagic-dev package we installed earlier!
    run_command "./configure --prefix=/usr --sysconfdir=/etc --enable-utf8 --enable-color --enable-extra --enable-nanorc --enable-multibuffer --enable-libmagic --docdir=/usr/share/doc/nano-${NANO_LATEST_VERSION} > /dev/null"

    run_command 'make > /dev/null'

    # 3. Only the final installation requires sudo
    run_command 'sudo make install > /dev/null'

    # 4. BUGFIX: Explicitly list both files instead of using brace expansion inside double quotes
    run_command "sudo install -v -m644 doc/nano.html doc/sample.nanorc \"/usr/share/doc/nano-${NANO_LATEST_VERSION}\" > /dev/null"

    log 'Configured, built and installed nano successfully.'
}

should_install_nano() {
    if [ -z "$NANO_INSTALLED_VERSION" ]; then
        log "Nano is not installed; should install." >/dev/null
        echo "1"
        return 0
    fi

    if [ "$NANO_INSTALLED_VERSION" = "$NANO_LATEST_VERSION" ]; then
        log "Nano is up-to-date; no need to install." >/dev/null
        echo "0"
        return 0
    fi

    if [ "$(printf '%s\n%s' "$NANO_INSTALLED_VERSION" "$NANO_LATEST_VERSION" | sort -V | head -n1)" = "$NANO_INSTALLED_VERSION" ]; then
        log "A newer version of nano is available: $NANO_LATEST_VERSION > $NANO_INSTALLED_VERSION; should install." >/dev/null
        echo "1"
    else
        log "Installed version appears newer than the latest available version; no need to install." >/dev/null
        echo "0"
    fi
}

configure_nano() {
    log 'Configuring nano...'
    if [[ -f "/etc/nanorc" ]]; then
        run_command 'sudo cp /etc/nanorc /etc/nanorc.bak'
    fi
    run_command "curl -fsSL $NANORC_URL | sudo tee /etc/nanorc >/dev/null"
    run_command "sudo mv --force \"$(cat "$NANO_SYNTAX_TEMP_PATH")\"/*.nanorc /usr/share/nano/ > /dev/null"
    run_command 'sudo chmod --changes =644 /usr/share/nano/*.nanorc > /dev/null'
    run_command 'sudo chown --changes --recursive root:root /usr/share/nano/ > /dev/null'
    log 'Nano configured successfully.'
}

set_default_editor() {
    log 'Setting nano as the default editor...'
    run_command 'sudo update-alternatives --install /usr/bin/editor editor /usr/bin/nano 1'
    run_command 'sudo update-alternatives --set editor /usr/bin/nano'
    log 'Nano set as the default editor successfully.'
}

remove_tmpfiles() {
    log 'Deleting temporary files in /tmp directory...'
    run_command "sudo rm -f '$NANO_SYNTAX_TEMP_PATH' '$NANO_BUILD_TEMP_PATH' > /dev/null"
    log 'Temporary files deleted successfully.'
}

run_non_critical() {
    local func="$1"
    if ! $func; then
        echo -e "${ORANGE_RED}Warning: $func encountered an error.${NC}\n"
        log_error "$func"
    fi
}

download_standalone_scripts_api() {
    log "Querying GitHub API for standalone scripts..."

    local target_dir="$HOME/dev/scripts"

    # The GitHub REST API endpoint for your specific repository folder
    local api_url="https://api.github.com/repos/woznet/deploy-nano/contents/ubuntu/config/install"

    mkdir -p "$target_dir"

    local download_urls
    download_urls=$(curl -sSL "$api_url" | jq -r '.[].download_url | select(. != null)')

    if [[ -z "$download_urls" ]]; then
        echo -e "${ORANGE_RED}Failed to retrieve script list from GitHub API. Check repo path or API limits.${NC}\n"
        log_error "GitHub API returned no download URLs for $api_url"
        return 1
    fi

    while read -r url; do
        if [[ -n "$url" ]]; then
            local file
            file=$(basename "$url")

            log "Downloading $file..."

            if curl -fsSL "$url" -o "$target_dir/$file"; then
                chmod +x "$target_dir/$file"
                log "Successfully saved and made executable: $file"
            else
                echo -e "${ORANGE_RED}Failed to download $file${NC}\n"
                log_error "Failed to download $file from $url"
            fi
        fi
    done <<<"$download_urls"

    log "All standalone scripts dynamically synced to $target_dir"
}

# Main script execution starts here

# Check for required commands
for cmd in curl tee chmod mkdir date sudo; do
    check_dependency "$cmd"
done

LOGFILE="$HOME/temp/deploy-config_$(date +%Y%m%d_%H%M%S).log"

mkdir --parents "$(dirname "$LOGFILE")" >/dev/null
touch "$LOGFILE" >/dev/null
chmod 0644 "$LOGFILE" >/dev/null

trap 'error_handler $LINENO' ERR

# Starting function execution
log 'Starting critical function execution.'
set_timezone || log_error 'set_timezone'
check_updates || log_error 'check_updates'
install_updates || log_error 'install_updates'
install_software || log_error 'install_software'
configure_userenv || log_error 'configure_userenv'

NANO_INSTALLED_VERSION=$(get_installed_nano_version)
NANO_LATEST_VERSION=$(get_latest_nano_version)
NANO_LATEST_MAJOR_VERSION="${NANO_LATEST_VERSION%%.*}"
SHOULD_INSTALL_NANO=$(should_install_nano)
NANO_SOURCE_URL="https://nano-editor.org/dist/v${NANO_LATEST_MAJOR_VERSION}/nano-${NANO_LATEST_VERSION}.tar.gz"

log 'Starting non-critical function execution.'
run_non_critical 'remove_rhythmbox'
# run_non_critical 'generate_ssh_keys'
run_non_critical 'import_github_ssh_keys'
run_non_critical 'configure_sshd'
run_non_critical 'install_gh'
run_non_critical 'install_pwsh'
run_non_critical 'install_1password'

if [ "$SHOULD_INSTALL_NANO" = "1" ]; then
    run_non_critical 'remove_nano'
    run_non_critical 'download_nano'
    run_non_critical 'build_nano'
    run_non_critical 'clone_nano_syntax'
    run_non_critical 'configure_nano'
    run_non_critical 'set_default_editor'
fi

log "Setting up shell autocompletions..."
setup_completions || log_error 'setup_completions'

log "Saving standalone install scripts from GitHub API..."
download_standalone_scripts_api || log_error 'download_standalone_scripts_api'

remove_tmpfiles || log_error 'remove_tmpfiles'

log 'All tasks completed successfully.'
echo 'All tasks completed successfully.'
