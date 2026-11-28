#!/usr/bin/env bash
# Shared library for install scripts
# Source this at the top of install scripts:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "${SCRIPT_DIR}/../lib/common.sh"  # adjust path as needed

# === Colors ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# === Logging ===
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${BLUE}${BOLD}==> $1${NC}"; }

# === OS Detection ===
# Sets: OS (macos|ubuntu), SHELL_NAME (zsh|bash), PKG_MGR (brew|apt)
# shellcheck disable=SC2034  # vars used by caller (bootstrap.sh)
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        SHELL_NAME="zsh"
        PKG_MGR="brew"
    elif [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" == "ubuntu" ]]; then
            OS="ubuntu"
            SHELL_NAME="zsh"
            PKG_MGR="apt"
        else
            log_error "Unsupported Linux distribution: $ID"
            exit 1
        fi
    else
        log_error "Unsupported operating system: ${OSTYPE:-unknown}"
        exit 1
    fi
}

# === Homebrew Permission Check (macOS) ===
check_brew_permissions() {
    command -v brew &>/dev/null || return 0

    local brew_prefix
    brew_prefix="$(brew --prefix)"

    local prefix_owner
    prefix_owner="$(stat -f "%Su" "$brew_prefix" 2>/dev/null || stat -c "%U" "$brew_prefix" 2>/dev/null)"
    if [[ -n "$prefix_owner" ]] && [[ "$prefix_owner" != "$USER" ]]; then
        log_error "Homebrew prefix ${brew_prefix} is owned by '${prefix_owner}', not '${USER}'"
        log_error "Switch to '${prefix_owner}' or fix ownership before running this script"
        exit 1
    fi

    if [[ ! -w "$brew_prefix" ]]; then
        log_error "No write permission on ${brew_prefix}"
        log_error "Run: sudo chown -R \${USER} ${brew_prefix}"
        exit 1
    fi

    if [[ -d "${brew_prefix}/Cellar" ]] && [[ ! -w "${brew_prefix}/Cellar" ]]; then
        log_error "No write permission on ${brew_prefix}/Cellar"
        log_error "Run: sudo chown -R \${USER} ${brew_prefix}/Cellar"
        exit 1
    fi

    log_info "Homebrew permissions OK (owner: ${prefix_owner}, prefix: ${brew_prefix})"
}

# === Brewfile Trust (macOS) ===
# Homebrew 6+ refuses formulae and casks from non-official taps until they are
# trusted. Taps the Brewfile's taps, then trusts exactly the brew and cask
# entries marked `trusted: true`, by name: never a whole tap, which would also
# trust whatever that tap adds later. A Homebrew without `brew trust` is left
# alone. Used by bootstrap before `brew bundle`, and by Brew Bundle Check.
trust_brewfile_entries() {  # BREWFILE
    brew help trust >/dev/null 2>&1 || return 0
    local line kind name
    local tap_re='^[[:space:]]*tap[[:space:]]+"([^"]+)"'
    local entry_re='^[[:space:]]*(brew|cask)[[:space:]]+"([^"]+)"[^#]*trusted:[[:space:]]*true'
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ $tap_re ]] && { brew tap "${BASH_REMATCH[1]}" >/dev/null 2>&1 || true; }
    done < "$1"
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ $entry_re ]] || continue
        kind=${BASH_REMATCH[1]} name=${BASH_REMATCH[2]}
        [[ "$kind" == brew ]] && kind=formula
        if brew trust "--${kind}" "$name" >/dev/null 2>&1; then
            log_info "Trusted ${kind}: ${name}"
        else
            log_warn "Could not trust ${kind}: ${name}"
        fi
    done < "$1"
}
