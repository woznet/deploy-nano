#!/bin/bash
# deploy-completions.sh

# Ensure the completions directory exists
mkdir --parents "$HOME/.local/share/bash-completion/completions"

# ---------------------------------------------------------
# Generate autocomplete scripts (if the commands exist)
# ---------------------------------------------------------

if command -v dotnet >/dev/null 2>&1; then
    dotnet completions script bash > "$HOME/.local/share/bash-completion/completions/dotnet"
fi

if command -v gh >/dev/null 2>&1; then
    gh completion --shell bash > "$HOME/.local/share/bash-completion/completions/gh"
fi

if command -v rclone >/dev/null 2>&1; then
    rclone completion bash > "$HOME/.local/share/bash-completion/completions/rclone"
fi

if command -v op >/dev/null 2>&1; then
    op completion bash > "$HOME/.local/share/bash-completion/completions/op"
fi

if command -v pip >/dev/null 2>&1; then
    pip completion --bash > "$HOME/.local/share/bash-completion/completions/pip"
fi
