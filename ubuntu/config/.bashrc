# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
  *i*) ;;
  *) return ;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoredups

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
# HISTSIZE=1000
# HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
  debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
  xterm-color | *-256color) color_prompt=yes ;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
  if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
    # We have color support; assume it's compliant with Ecma-48
    # (ISO/IEC-6429). (Lack of such support is extremely rare, and such
    # a case would tend to support setf rather than setaf.)
    color_prompt=yes
  else
    color_prompt=
  fi
fi

# If this is an xterm set the title to user@host:dir
case "$TERM" in
  xterm* | rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
  *) ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
  test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
  alias ls='ls --color=auto'
  alias dir='dir --color=auto'
  alias vdir='vdir --color=auto'

  alias grep='grep --color=auto'
  alias fgrep='fgrep --color=auto'
  alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
  . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

#-+-#-+-#-+-#-+-#-+-#-+-#-+-#-+-#-+-#-+-#-+-#-+-#
##########################################################################
## Custom Config Below
##########################################################################
#-+-#-+-#-+-#-+-#-+-#-+-#-+-#-+-#-+-#-+-#-+-#-+-#

#-+-#-+-#-+-#-+-#
#-+-#-+-#-+-#-+-#

if [ $EUID == 0 ]; then
  export PS1="\[\033[38;5;160m\]\u\[\033[38;5;32m\]@\[\033[38;5;112m\]\h\[\033[38;5;32m\]:\[\033[38;5;166m\]\w \[\033[38;5;32m\]\$ \[\033[0m\]"
else
  export PS1="\[\033[38;5;214m\]\u\[\033[38;5;32m\]@\[\033[38;5;112m\]\h\[\033[38;5;32m\]:\[\033[38;5;166m\]\w \[\033[38;5;32m\]\$ \[\033[0m\]"
fi

export PS2="  "

#-+-#-+-#-+-#-+-#
if command -v most >/dev/null 2>&1; then
  # Color man pages
  export PAGER="most"
fi

#-+-#-+-#-+-#-+-#

### Add ~/.local/bin and ~/bin to PATH for pip/python and dev
# export PATH="$PATH:$HOME/.local/bin:$HOME/bin"
for d in "$HOME/.local/bin" "$HOME/bin"; do [[ -d "$d" ]] && PATH="$PATH:$d"; done
export PATH

#-+-#-+-#-+-#-+-#

if [[ -d "$HOME/.nvm" ]]; then
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"                   # This loads nvm
  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" # This loads nvm bash_completion
fi


for npm_path in $(which -a npm | grep -v '^/mnt/c/' | uniq); do
  node_path="$(dirname "$npm_path")/node"
  if [[ -x "$node_path" ]]; then
    echo "Using npm: $npm_path ($( "$npm_path" --version ))"
    echo "Using node: $node_path ($( "$node_path" --version ))"
    export PATH="$(npm prefix -g)/bin:$PATH"
    ## npm bash completion
    source <("$npm_path" completion)
    if [[ $(which tldr) ]]; then
      source "$(dirname $(realpath $(which tldr)))/completion/bash/tldr"
    fi
    break
  fi
done

#-+-#-+-#-+-#-+-#

# gh bash completion
# if command -v gh >/dev/null 2>&1; then
#   source <(gh completion --shell bash)
# fi

# aws bash completion
# if command -v aws >/dev/null 2>&1; then
#   complete -C '/usr/local/bin/aws_completer' aws
# fi

# 1Password cli bash completion
# if command -v op >/dev/null 2>&1; then
#   source <(op completion bash)
# fi

# pip bash completion
# if command -v pip >/dev/null 2>&1; then
#  source <(pip completion --bash)
# fi

# dotnet bash completion
if command -v dotnet >/dev/null 2>&1; then
  export DOTNET_CLI_TELEMETRY_OPTOUT='true'
#   if [[ $(dotnet --version 2>/dev/null | cut -d. -f1) -ge 10 ]]; then
#     source <(dotnet completions script bash)
#   else
#     _dotnet_bash_complete() {
#       local cur="${COMP_WORDS[COMP_CWORD]}" IFS=$'\n'
#       local candidates
#
#       read -d '' -ra candidates < <(dotnet complete --position "${COMP_POINT}" "${COMP_LINE}" 2>/dev/null)
#       read -d '' -ra COMPREPLY < <(compgen -W "${candidates[*]:-}" -- "$cur")
#     }
#
#     complete -f -F _dotnet_bash_complete dotnet
#   fi
fi

#-+-#-+-#-+-#-+-#

# verify history cmd before executing
shopt -s histverify

#-+-#-+-#-+-#-+-#

#-+-#-+-#-+-#-+-#

# Immediatedly add command to history
export PROMPT_COMMAND="history -a; history -c; history -r; $PROMPT_COMMAND"

#-+-#-+-#-+-#-+-#

HISTSIZE=5000
HISTFILESIZE=10000

#-+-#-+-#-+-#-+-#
# SharePoint tenant domain
# export SPFX_SERVE_TENANT_DOMAIN=tenant.sharepoint.com
#-+-#-+-#-+-#-+-#

#-+-#-+-#-+-#-+-#
