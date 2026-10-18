#!/usr/bin/env bash
#
# create-user.sh - Create a fully configured user account on Ubuntu Server.
#
# Covers identity (comment/full name, UID, system account), home directory and
# login shell, primary and supplementary groups, sudo access, the password
# (prompt, stdin, random, or locked), password aging and account expiry, and
# SSH authorized keys (inline, from files, or via ssh-import-id).
#
# Everything is validated before the account is created. Privileged commands
# are run through sudo when the script is not already running as root.
# Run with --help for usage.

set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"

USERNAME=""
COMMENT=""
USER_UID=""
SYSTEM_ACCOUNT=0
HOME_DIR=""
CREATE_HOME=1
HOME_MODE="0750"
SKEL_DIR="/etc/skel"
LOGIN_SHELL="/bin/bash"
PRIMARY_GROUP=""
EXTRA_GROUPS=()
GRANT_SUDO=0
SUDO_NOPASSWD=0
PASSWORD_MODE="" # prompt | stdin | random | none
PASSWORD=""
FORCE_CHANGE=0
EXPIRE_DATE=""
INACTIVE_DAYS=""
MIN_DAYS=""
MAX_DAYS=""
WARN_DAYS=""
SSH_KEYS=()
SSH_KEY_FILES=()
SSH_IMPORT_IDS=()
DRY_RUN=0

SUDO=()
TMP_DIR=""
KEY_COUNT=0
ACCOUNT_CREATED=0

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [options] USERNAME

Create a user account on Ubuntu Server.

Identity:
  -c, --comment TEXT        Full name / GECOS field, e.g. "Jane Doe"
  -u, --uid UID             Numeric user ID (default: next free UID)
      --system              Create a system account (UID below UID_MIN)

Home and shell:
  -d, --home DIR            Home directory (default: /home/USERNAME)
  -M, --no-home             Do not create a home directory
      --home-mode MODE      Home directory permissions (default: 0750)
  -k, --skel DIR            Skeleton directory to copy (default: /etc/skel)
  -s, --shell SHELL         Login shell (default: /bin/bash; use
                            /usr/sbin/nologin for a service account)

Groups and privileges:
  -g, --group GROUP         Primary group (default: new group named USERNAME)
  -G, --groups G1,G2,...    Supplementary groups (repeatable)
  -S, --sudo                Add to the 'sudo' group (sudo asks for password)
      --sudo-nopasswd       Install a sudoers rule: sudo without a password

Password (pick one; default is --password-prompt on a terminal):
  -p, --password-prompt     Prompt for the password
      --password-stdin      Read the password from the first line of stdin
  -r, --random-password     Generate a random password and print it once
  -L, --no-password         Lock the password (SSH key login only)
  -f, --force-change        Require a password change at first login

Password aging and account expiry:
  -e, --expire DATE         Disable the account on DATE (YYYY-MM-DD)
  -I, --inactive DAYS       Disable the account DAYS after password expiry
      --min-days DAYS       Minimum days between password changes
      --max-days DAYS       Maximum days a password stays valid
      --warn-days DAYS      Days of warning before the password expires

SSH access:
      --ssh-key KEY         Add a public key to authorized_keys (repeatable)
      --ssh-key-file FILE   Add the keys in FILE (repeatable)
      --ssh-import-id ID    Import keys with ssh-import-id, e.g. gh:alice
                            or lp:alice (repeatable; needs network access)

Other:
  -n, --dry-run             Validate and print the commands without running them
  -h, --help                Show this help and exit

Examples:
  $SCRIPT_NAME -c "Jane Doe" -S --ssh-key-file jane.pub jane
  $SCRIPT_NAME -c "Bob Smith" -r -f -G docker,adm --max-days 90 bob
  $SCRIPT_NAME --system -M -L -s /usr/sbin/nologin -c "Backup service" backup-svc
  printf '%s\\n' "\$PW" | $SCRIPT_NAME --password-stdin -e 2027-06-30 contractor
EOF
}

log() {
    printf '%s: %s\n' "$SCRIPT_NAME" "$*" >&2
}

warn() {
    printf '%s: warning: %s\n' "$SCRIPT_NAME" "$*" >&2
}

die() {
    printf '%s: error: %s\n' "$SCRIPT_NAME" "$*" >&2
    exit 1
}

# Run a privileged command (via sudo when not root), or print it on --dry-run.
run() {
    local cmd=("${SUDO[@]}" "$@")
    if ((DRY_RUN)); then
        printf '+' >&2
        printf ' %q' "${cmd[@]}" >&2
        printf '\n' >&2
        return 0
    fi
    "${cmd[@]}"
}

on_exit() {
    local status=$?
    if [[ -n $TMP_DIR ]]; then
        rm -rf -- "$TMP_DIR"
    fi
    if ((status != 0 && ACCOUNT_CREATED && ! DRY_RUN)); then
        warn "setup failed after '$USERNAME' was created; the account may be incomplete"
        warn "review it, or remove it with: sudo userdel -r $USERNAME"
    fi
}

need_arg() {
    [[ $# -ge 2 && -n $2 ]] || die "option $1 requires a value"
}

set_password_mode() {
    if [[ -n $PASSWORD_MODE && $PASSWORD_MODE != "$1" ]]; then
        die "choose only one of --password-prompt, --password-stdin, --random-password, --no-password"
    fi
    PASSWORD_MODE=$1
}

parse_args() {
    local split
    while (($# > 0)); do
        case $1 in
        -c | --comment)
            need_arg "$@"
            COMMENT=$2
            shift
            ;;
        -u | --uid)
            need_arg "$@"
            USER_UID=$2
            shift
            ;;
        --system) SYSTEM_ACCOUNT=1 ;;
        -d | --home)
            need_arg "$@"
            HOME_DIR=$2
            shift
            ;;
        -M | --no-home) CREATE_HOME=0 ;;
        --home-mode)
            need_arg "$@"
            HOME_MODE=$2
            shift
            ;;
        -k | --skel)
            need_arg "$@"
            SKEL_DIR=$2
            shift
            ;;
        -s | --shell)
            need_arg "$@"
            LOGIN_SHELL=$2
            shift
            ;;
        -g | --group)
            need_arg "$@"
            PRIMARY_GROUP=$2
            shift
            ;;
        -G | --groups)
            need_arg "$@"
            IFS=',' read -ra split <<<"$2"
            EXTRA_GROUPS+=("${split[@]}")
            shift
            ;;
        -S | --sudo) GRANT_SUDO=1 ;;
        --sudo-nopasswd) SUDO_NOPASSWD=1 ;;
        -p | --password-prompt) set_password_mode prompt ;;
        --password-stdin) set_password_mode stdin ;;
        -r | --random-password) set_password_mode random ;;
        -L | --no-password) set_password_mode none ;;
        -f | --force-change) FORCE_CHANGE=1 ;;
        -e | --expire)
            need_arg "$@"
            EXPIRE_DATE=$2
            shift
            ;;
        -I | --inactive)
            need_arg "$@"
            INACTIVE_DAYS=$2
            shift
            ;;
        --min-days)
            need_arg "$@"
            MIN_DAYS=$2
            shift
            ;;
        --max-days)
            need_arg "$@"
            MAX_DAYS=$2
            shift
            ;;
        --warn-days)
            need_arg "$@"
            WARN_DAYS=$2
            shift
            ;;
        --ssh-key)
            need_arg "$@"
            SSH_KEYS+=("$2")
            shift
            ;;
        --ssh-key-file)
            need_arg "$@"
            SSH_KEY_FILES+=("$2")
            shift
            ;;
        --ssh-import-id)
            need_arg "$@"
            SSH_IMPORT_IDS+=("$2")
            shift
            ;;
        -n | --dry-run) DRY_RUN=1 ;;
        -h | --help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*) die "unknown option: $1 (see --help)" ;;
        *)
            [[ -z $USERNAME ]] || die "unexpected argument: $1"
            USERNAME=$1
            ;;
        esac
        shift
    done
    if (($# > 0)); then
        [[ -z $USERNAME && $# -eq 1 ]] || die "expected exactly one USERNAME"
        USERNAME=$1
    fi
}

check_days() {
    local option=$1 value=$2
    if [[ -n $value && ! $value =~ ^[0-9]+$ ]]; then
        die "$option must be a whole number of days, got '$value'"
    fi
}

is_valid_date() {
    [[ $1 =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
    [[ $(date -d "$1" +%F 2>/dev/null) == "$1" ]]
}

validate_args() {
    [[ -n $USERNAME ]] || die "missing USERNAME (see --help)"
    if [[ ! $USERNAME =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        die "invalid username '$USERNAME': use up to 32 lowercase letters, digits, '_' or '-', starting with a letter or '_'"
    fi
    if [[ $COMMENT == *[:$'\n']* ]]; then
        die "comment must not contain ':' or newlines"
    fi
    if [[ -n $USER_UID && ! $USER_UID =~ ^[0-9]+$ ]]; then
        die "UID must be a whole number, got '$USER_UID'"
    fi
    if [[ ! $HOME_MODE =~ ^0?[0-7]{3}$ ]]; then
        die "--home-mode must be an octal mode such as 0750, got '$HOME_MODE'"
    fi

    HOME_DIR=${HOME_DIR:-/home/$USERNAME}
    [[ $HOME_DIR == /* ]] || die "home directory must be an absolute path, got '$HOME_DIR'"

    check_days --inactive "$INACTIVE_DAYS"
    check_days --min-days "$MIN_DAYS"
    check_days --max-days "$MAX_DAYS"
    check_days --warn-days "$WARN_DAYS"
    if [[ -n $EXPIRE_DATE ]]; then
        is_valid_date "$EXPIRE_DATE" || die "invalid --expire date '$EXPIRE_DATE' (expected YYYY-MM-DD)"
        if [[ $EXPIRE_DATE < $(date +%F) ]]; then
            warn "--expire date $EXPIRE_DATE is in the past; the account will be disabled immediately"
        fi
    fi

    if [[ -z $PASSWORD_MODE ]]; then
        [[ -t 0 ]] || die "no terminal for a password prompt; use --password-stdin, --random-password or --no-password"
        PASSWORD_MODE=prompt
    fi
    if ((FORCE_CHANGE)) && [[ $PASSWORD_MODE == none ]]; then
        die "--force-change needs a password; it cannot be combined with --no-password"
    fi
    if ((! CREATE_HOME)) && ((${#SSH_KEYS[@]} + ${#SSH_KEY_FILES[@]} + ${#SSH_IMPORT_IDS[@]} > 0)); then
        die "SSH keys need a home directory; remove --no-home"
    fi
    if ((GRANT_SUDO && ! SUDO_NOPASSWD)) && [[ $PASSWORD_MODE == none ]]; then
        warn "--sudo with a locked password: the user cannot authenticate to sudo (consider --sudo-nopasswd)"
    fi
    if ((GRANT_SUDO)); then
        EXTRA_GROUPS+=(sudo)
    fi

    # Drop empty entries (e.g. "-G a,,b") and duplicates.
    local group unique=()
    local -A seen=()
    for group in "${EXTRA_GROUPS[@]}"; do
        [[ -n $group && -z ${seen[$group]:-} ]] || continue
        seen[$group]=1
        unique+=("$group")
    done
    EXTRA_GROUPS=("${unique[@]}")
}

preflight() {
    local cmd group
    for cmd in useradd usermod chpasswd chage getent install id; do
        command -v "$cmd" >/dev/null || die "required command not found: $cmd"
    done
    if ((${#SSH_IMPORT_IDS[@]})); then
        command -v ssh-import-id >/dev/null || die "ssh-import-id not found; install it with: sudo apt-get install -y ssh-import-id"
    fi
    if ((SUDO_NOPASSWD)); then
        command -v visudo >/dev/null || die "visudo not found; is sudo installed?"
    fi

    if [[ $EUID -ne 0 ]]; then
        command -v sudo >/dev/null || die "not running as root and sudo is not installed"
        SUDO=(sudo)
        if ((! DRY_RUN)); then
            sudo -v || die "sudo authentication failed"
        fi
    fi

    if getent passwd "$USERNAME" >/dev/null; then
        die "user '$USERNAME' already exists"
    fi
    if [[ -n $USER_UID ]] && getent passwd "$USER_UID" >/dev/null; then
        die "UID $USER_UID is already in use"
    fi
    if [[ -n $PRIMARY_GROUP ]]; then
        getent group "$PRIMARY_GROUP" >/dev/null || die "primary group '$PRIMARY_GROUP' does not exist"
    elif getent group "$USERNAME" >/dev/null; then
        die "group '$USERNAME' already exists; pass '-g $USERNAME' to use it as the primary group"
    fi
    for group in "${EXTRA_GROUPS[@]}"; do
        getent group "$group" >/dev/null || die "group '$group' does not exist (create it with: sudo groupadd $group)"
    done

    [[ -x $LOGIN_SHELL ]] || die "login shell '$LOGIN_SHELL' does not exist or is not executable"
    case $LOGIN_SHELL in
    */nologin | */false) ;;
    *)
        grep -qxF -- "$LOGIN_SHELL" /etc/shells ||
            warn "'$LOGIN_SHELL' is not listed in /etc/shells; some services may refuse logins"
        ;;
    esac

    if ((CREATE_HOME)); then
        [[ ! -e $HOME_DIR ]] || die "home directory '$HOME_DIR' already exists"
        [[ -d $SKEL_DIR ]] || die "skeleton directory '$SKEL_DIR' does not exist"
    fi

    TMP_DIR=$(mktemp -d)
}

# Validate one authorized_keys line and append it to the staged file.
add_key_line() {
    local line=$1 source=$2
    [[ -n ${line//[[:space:]]/} && $line != \#* ]] || return 0
    if command -v ssh-keygen >/dev/null; then
        printf '%s\n' "$line" >"$TMP_DIR/check.pub"
        ssh-keygen -l -f "$TMP_DIR/check.pub" >/dev/null 2>&1 ||
            die "invalid SSH public key in $source: ${line:0:40}..."
    fi
    printf '%s\n' "$line" >>"$TMP_DIR/authorized_keys"
    KEY_COUNT=$((KEY_COUNT + 1))
}

collect_ssh_keys() {
    local key file line lines=()
    for key in "${SSH_KEYS[@]}"; do
        add_key_line "$key" "--ssh-key"
    done
    for file in "${SSH_KEY_FILES[@]}"; do
        [[ -r $file ]] || die "cannot read SSH key file '$file'"
        mapfile -t lines <"$file"
        for line in "${lines[@]}"; do
            add_key_line "$line" "$file"
        done
    done
}

prepare_sudoers() {
    ((SUDO_NOPASSWD)) || return 0
    printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$USERNAME" >"$TMP_DIR/sudoers"
    run visudo -c -f "$TMP_DIR/sudoers" >/dev/null || die "generated sudoers rule failed validation"
}

generate_password() {
    head -c 48 /dev/urandom | base64 | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c 1-20
}

read_password() {
    local confirm
    case $PASSWORD_MODE in
    prompt)
        IFS= read -rsp "New password for $USERNAME: " PASSWORD </dev/tty
        printf '\n' >&2
        IFS= read -rsp "Retype password: " confirm </dev/tty
        printf '\n' >&2
        [[ $PASSWORD == "$confirm" ]] || die "passwords do not match"
        ;;
    stdin)
        IFS= read -r PASSWORD || [[ -n $PASSWORD ]] || die "no password received on stdin"
        ;;
    random)
        PASSWORD=$(generate_password)
        ;;
    none)
        return 0
        ;;
    esac
    ((${#PASSWORD} >= 8)) || die "password must be at least 8 characters"
}

create_account() {
    local args=(-s "$LOGIN_SHELL" -d "$HOME_DIR")
    if [[ -n $COMMENT ]]; then
        args+=(-c "$COMMENT")
    fi
    if ((CREATE_HOME)); then
        args+=(-m -k "$SKEL_DIR")
    else
        args+=(-M)
    fi
    if [[ -n $USER_UID ]]; then
        args+=(-u "$USER_UID")
    fi
    if ((SYSTEM_ACCOUNT)); then
        args+=(-r)
    fi
    if [[ -n $PRIMARY_GROUP ]]; then
        args+=(-g "$PRIMARY_GROUP")
    fi
    if ((${#EXTRA_GROUPS[@]})); then
        args+=(-G "$(
            IFS=,
            printf '%s' "${EXTRA_GROUPS[*]}"
        )")
    fi
    if [[ -n $EXPIRE_DATE ]]; then
        args+=(-e "$EXPIRE_DATE")
    fi
    if [[ -n $INACTIVE_DAYS ]]; then
        args+=(-f "$INACTIVE_DAYS")
    fi

    log "creating user '$USERNAME'"
    run useradd "${args[@]}" -- "$USERNAME"
    ACCOUNT_CREATED=1

    if ((CREATE_HOME)); then
        run chmod "$HOME_MODE" "$HOME_DIR"
    fi
}

set_password() {
    if [[ $PASSWORD_MODE == none ]]; then
        log "locking password (SSH key login only)"
        run usermod -L "$USERNAME"
        return 0
    fi
    log "setting password"
    # A here-string keeps the password off the command line and out of ps.
    run chpasswd <<<"$USERNAME:$PASSWORD"
}

set_aging() {
    local args=()
    if [[ -n $MIN_DAYS ]]; then
        args+=(-m "$MIN_DAYS")
    fi
    if [[ -n $MAX_DAYS ]]; then
        args+=(-M "$MAX_DAYS")
    fi
    if [[ -n $WARN_DAYS ]]; then
        args+=(-W "$WARN_DAYS")
    fi
    if ((FORCE_CHANGE)); then
        args+=(-d 0)
    fi
    if ((${#args[@]})); then
        log "applying password aging policy"
        run chage "${args[@]}" "$USERNAME"
    fi
}

install_ssh_keys() {
    ((KEY_COUNT + ${#SSH_IMPORT_IDS[@]} > 0)) || return 0
    local group ssh_dir="$HOME_DIR/.ssh"
    local auth_keys="$ssh_dir/authorized_keys"
    if ((DRY_RUN)); then
        group=${PRIMARY_GROUP:-$USERNAME}
    else
        group=$(id -gn "$USERNAME")
    fi

    log "installing SSH authorized keys"
    run install -d -m 0700 -o "$USERNAME" -g "$group" "$ssh_dir"
    if ((KEY_COUNT)); then
        run install -m 0600 -o "$USERNAME" -g "$group" "$TMP_DIR/authorized_keys" "$auth_keys"
    fi
    if ((${#SSH_IMPORT_IDS[@]})); then
        run ssh-import-id -o "$auth_keys" "${SSH_IMPORT_IDS[@]}"
        run chown "$USERNAME:$group" "$auth_keys"
        run chmod 0600 "$auth_keys"
    fi
}

install_sudoers() {
    ((SUDO_NOPASSWD)) || return 0
    log "installing passwordless sudo rule"
    run install -m 0440 -o root -g root "$TMP_DIR/sudoers" "/etc/sudoers.d/90-$USERNAME"
}

print_summary() {
    if ((DRY_RUN)); then
        log "dry run complete; no changes were made"
        return 0
    fi
    local home_desc="$HOME_DIR"
    if ((! CREATE_HOME)); then
        home_desc="$HOME_DIR (not created)"
    fi
    printf '\nUser %s created.\n' "$USERNAME"
    printf '  Identity: %s\n' "$(id "$USERNAME")"
    printf '  Home:     %s\n' "$home_desc"
    printf '  Shell:    %s\n' "$LOGIN_SHELL"
    if ((KEY_COUNT + ${#SSH_IMPORT_IDS[@]} > 0)); then
        printf '  SSH keys: %s/.ssh/authorized_keys\n' "$HOME_DIR"
    fi
    if ((SUDO_NOPASSWD)); then
        printf '  Sudo:     passwordless (/etc/sudoers.d/90-%s)\n' "$USERNAME"
    elif ((GRANT_SUDO)); then
        printf '  Sudo:     member of sudo group\n'
    fi
    printf '\nPassword aging:\n'
    run chage -l "$USERNAME" | sed 's/^/  /'
    if [[ $PASSWORD_MODE == random ]]; then
        printf '\nGenerated password (shown once, store it securely): %s\n' "$PASSWORD"
    fi
}

main() {
    trap on_exit EXIT
    parse_args "$@"
    validate_args
    preflight
    collect_ssh_keys
    prepare_sudoers
    read_password
    create_account
    set_password
    set_aging
    install_ssh_keys
    install_sudoers
    print_summary
}

main "$@"
