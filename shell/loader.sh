#!/usr/bin/env bash
# Smart Shell Loader
# Sources shell functions and aliases based on OS and available tools
# Replaces hardcoded ZSH_CUSTOM path

# Resolve script directory (works in both zsh and bash)
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    SHELL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [[ -n "${(%):-%x}" ]]; then
    SHELL_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
else
    SHELL_DIR="${MY_SETUP_DIR:-$HOME/my_setup}/shell"
fi

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    export SHELL_OS="macos"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" == "ubuntu" ]]; then
            export SHELL_OS="ubuntu"
        else
            export SHELL_OS="linux"
        fi
    else
        export SHELL_OS="linux"
    fi
else
    export SHELL_OS="unknown"
fi

# === Load Machine Config ===
# Non-secret, machine-specific settings (DATA_DIR, OP_SSH_SIGN_PATH, etc.)
[[ -f "${HOME}/.config/my_setup/config" ]] && source "${HOME}/.config/my_setup/config"

# === Load Functions ===

# Load cross-platform functions
if [[ -d "${SHELL_DIR}/functions" ]]; then
    for file in "${SHELL_DIR}/functions"/*.sh; do
        [[ -f "$file" ]] && source "$file"
    done
fi

# Load platform-specific functions
if [[ -d "${SHELL_DIR}/platform/${SHELL_OS}" ]]; then
    for file in "${SHELL_DIR}/platform/${SHELL_OS}"/*.sh; do
        [[ -f "$file" ]] && source "$file"
    done
fi

# === Load Aliases ===

if [[ -d "${SHELL_DIR}/aliases" ]]; then
    for file in "${SHELL_DIR}/aliases"/*.sh; do
        [[ -f "$file" ]] && source "$file"
    done
fi


# === Export Path ===
export MY_SETUP_DIR="$(dirname "$SHELL_DIR")"
export MY_SETUP_SHELL_DIR="$SHELL_DIR"

# === Optional: Debug Info ===
# Uncomment for troubleshooting
# echo "Shell loader initialized:"
# echo "  OS: $SHELL_OS"
# echo "  Shell dir: $SHELL_DIR"
# echo "  Setup dir: $MY_SETUP_DIR"
