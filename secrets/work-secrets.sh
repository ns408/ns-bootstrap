#!/usr/bin/env bash
# Git identity for the work profile, on a company-managed Mac.
#
# Writes ~/.config/ns-bootstrap/gitconfig (the work name, email and signing,
# plus ns-bootstrap's shared git settings) and includes it from
# ~/.config/git/config. ~/.gitconfig is never written: git reads it after the
# include, so whatever IT or you set there wins.
#
# Values come from the environment, then ~/.config/ns-bootstrap/settings, then
# a prompt (install/lib/settings.sh):
#   NS_BOOTSTRAP_GIT_NAME, NS_BOOTSTRAP_GIT_EMAIL
#   NS_BOOTSTRAP_GIT_SIGNING       none (default), ssh-file, 1password or gpg
#   NS_BOOTSTRAP_GIT_SIGNING_KEY   key file, public key, or GPG key ID
#   NS_BOOTSTRAP_SECRETS_PROVIDER  none (default) or 1password, to keep the
#                                  name and email in a 1Password item too
#   NS_BOOTSTRAP_OP_VAULT, NS_BOOTSTRAP_OP_ACCOUNT  which vault and account
#
# Usage: work-secrets.sh [--yes]   (--yes: never prompt; missing values fail)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "${PROJECT_ROOT}/install/lib/common.sh"
source "${PROJECT_ROOT}/install/lib/settings.sh"
source "${PROJECT_ROOT}/install/lib/template.sh"

NONINTERACTIVE=false
for arg in "$@"; do
    case "$arg" in
        --yes|-y) NONINTERACTIVE=true ;;
        *) echo "Usage: $0 [--yes]" >&2; exit 2 ;;
    esac
done
# /dev/tty exists even without a terminal; only opening it tells.
{ : < /dev/tty; } 2>/dev/null || NONINTERACTIVE=true

OUT="${HOME}/.config/ns-bootstrap/gitconfig"
GIT_XDG="${XDG_CONFIG_HOME:-${HOME}/.config}/git/config"
# shellcheck disable=SC2088  # a literal ~: git expands it in include.path
INCLUDE_PATH="~/.config/ns-bootstrap/gitconfig"
OP_ITEM_NAME="ns-bootstrap"

fail() {                   # stderr, so it shows even inside $(...)
    log_error "$1" >&2
    exit 2
}

# ask LABEL CURRENT SETTING: the setting's value, else a prompt (CURRENT as default)
ask() {
    local label="$1" current="$2" setting="$3" value
    value="$(ns_setting "$setting" work)"
    if [[ -n "$value" ]]; then
        echo "$value"
        return
    fi
    if [[ "$NONINTERACTIVE" == true ]]; then
        [[ -n "$current" ]] && { echo "$current"; return; }
        fail "${label}: set ${setting} in the environment or ${NS_BOOTSTRAP_SETTINGS_FILE}"
    fi
    read -r -p "  ${label}${current:+ [${current}]}: " value < /dev/tty
    echo "${value:-$current}"
}

# --- 1Password: optional, and never fatal --------------------------------
PROVIDER="$(ns_setting NS_BOOTSTRAP_SECRETS_PROVIDER work)"
OP_VAULT="$(ns_setting NS_BOOTSTRAP_OP_VAULT work)"
OP_ACCOUNT_SETTING="$(ns_setting NS_BOOTSTRAP_OP_ACCOUNT work)"
[[ -n "$OP_ACCOUNT_SETTING" ]] && export OP_ACCOUNT="$OP_ACCOUNT_SETTING"   # op reads OP_ACCOUNT
op_ok=false
if [[ "$PROVIDER" == 1password ]]; then
    if ! command -v op &>/dev/null; then
        log_warn "1Password CLI (op) not found; continuing without 1Password."
    elif ! op account list &>/dev/null; then
        log_warn "1Password CLI is not signed in${OP_ACCOUNT:+ to ${OP_ACCOUNT}}; continuing without 1Password."
    else
        op_ok=true
    fi
fi
op_field() {               # FIELD: from the item's Git Work section, or nothing
    [[ "$op_ok" == true ]] || return 0
    op read "op://${OP_VAULT}/${OP_ITEM_NAME}/Git Work/$1" 2>/dev/null || true
}

# --- Identity ---------------------------------------------------------------
current() {                # KEY: from the file this script wrote last time
    [[ -f "$OUT" ]] && git config --file "$OUT" --get "$1" 2>/dev/null || true
}

# The last run's value, else 1Password's, offered as the default.
known() {                  # GIT_KEY OP_FIELD
    local v
    v="$(current "$1")"
    [[ -n "$v" ]] || v="$(op_field "$2")"
    echo "$v"
}

log_step "Work git identity"
GIT_NAME_WORK="$(ask "Work git name" "$(known user.name name)" NS_BOOTSTRAP_GIT_NAME)"
[[ -n "$GIT_NAME_WORK" && "$GIT_NAME_WORK" != *$'\n'* ]] || fail "The work git name cannot be empty"

GIT_EMAIL_WORK="$(ask "Work git email" "$(known user.email email)" NS_BOOTSTRAP_GIT_EMAIL)"
[[ "$GIT_EMAIL_WORK" =~ ^[^@[:space:]]+@[^@[:space:]]+$ ]] || fail "The work git email does not look like an address: ${GIT_EMAIL_WORK}"

# --- Signing ----------------------------------------------------------------
WORK_SIGNING="$(ns_setting NS_BOOTSTRAP_GIT_SIGNING work)"
if [[ "$(ns_setting_source NS_BOOTSTRAP_GIT_SIGNING work)" == default && "$NONINTERACTIVE" == false ]]; then
    read -r -p "  Commit signing: none, ssh-file, 1password or gpg [none]: " WORK_SIGNING < /dev/tty
    WORK_SIGNING="${WORK_SIGNING:-none}"
fi
WORK_SIGNING_KEY=""
OP_SSH_SIGN_PATH="${OP_SSH_SIGN_PATH:-/Applications/1Password.app/Contents/MacOS/op-ssh-sign}"
case "$WORK_SIGNING" in
    none) ;;
    ssh-file)
        key="$(current user.signingkey)"
        [[ -z "$key" && -f "${HOME}/.ssh/id_ed25519.pub" ]] && key="${HOME}/.ssh/id_ed25519.pub"
        WORK_SIGNING_KEY="$(ask "SSH key file to sign with (a .pub needs ssh-agent)" "$key" NS_BOOTSTRAP_GIT_SIGNING_KEY)"
        WORK_SIGNING_KEY="${WORK_SIGNING_KEY/#\~/$HOME}"
        [[ -f "$WORK_SIGNING_KEY" ]] || fail "No SSH key file at: ${WORK_SIGNING_KEY:-(none given)}"
        ;;
    1password)
        [[ -x "$OP_SSH_SIGN_PATH" ]] || fail "1Password's op-ssh-sign not found at ${OP_SSH_SIGN_PATH}; install 1Password or choose another signing method"
        WORK_SIGNING_KEY="$(ask "Public SSH key in 1Password (ssh-ed25519 AAAA...)" "$(current user.signingkey)" NS_BOOTSTRAP_GIT_SIGNING_KEY)"
        [[ "$WORK_SIGNING_KEY" == ssh-* || "$WORK_SIGNING_KEY" == ecdsa-* ]] || fail "Not an SSH public key: ${WORK_SIGNING_KEY:-(none given)}"
        ;;
    gpg)
        WORK_SIGNING_KEY="$(ask "GPG key ID to sign with" "$(current user.signingkey)" NS_BOOTSTRAP_GIT_SIGNING_KEY)"
        [[ "$WORK_SIGNING_KEY" =~ ^[0-9A-Fa-f]{8,40}$ ]] || fail "Not a GPG key ID: ${WORK_SIGNING_KEY:-(none given)}"
        ;;
    *) fail "NS_BOOTSTRAP_GIT_SIGNING must be none, ssh-file, 1password or gpg, not '${WORK_SIGNING}'" ;;
esac
export GIT_NAME_WORK GIT_EMAIL_WORK WORK_SIGNING WORK_SIGNING_KEY OP_SSH_SIGN_PATH

# --- Write the file and the include ------------------------------------------
mkdir -p "$(dirname "$OUT")"
new="$(work_gitconfig "${PROJECT_ROOT}/dotfiles/git/.gitconfig.template")"
if [[ -f "$OUT" && "$(cat "$OUT")" == "$new" ]]; then
    log_info "Up to date: ${OUT}"
else
    if [[ -f "$OUT" ]]; then
        backup="${HOME}/.dotfiles-backup/$(date +%Y%m%d%H%M%S)"
        mkdir -p "$backup"
        cp -p "$OUT" "${backup}/gitconfig"
        log_info "Backed up ${OUT} -> ${backup}/gitconfig"
    fi
    printf '%s\n' "$new" > "$OUT"
    log_info "Written: ${OUT}"
fi

mkdir -p "$(dirname "$GIT_XDG")"
if git config --file "$GIT_XDG" --get-all include.path 2>/dev/null | grep -qxF "$INCLUDE_PATH"; then
    log_info "Already included from ${GIT_XDG}"
else
    git config --file "$GIT_XDG" --add include.path "$INCLUDE_PATH"
    log_info "Included from ${GIT_XDG}"
fi

# --- 1Password copy, if asked for --------------------------------------------
if [[ "$op_ok" == true ]]; then
    fields=("Git Work.name[text]=${GIT_NAME_WORK}" "Git Work.email[text]=${GIT_EMAIL_WORK}")
    [[ -n "$WORK_SIGNING_KEY" ]] && fields+=("Git Work.signing_key[text]=${WORK_SIGNING_KEY}")
    if op item get "$OP_ITEM_NAME" --vault="$OP_VAULT" &>/dev/null; then
        op item edit "$OP_ITEM_NAME" --vault="$OP_VAULT" "${fields[@]}" >/dev/null \
            && log_info "Updated 1Password item ${OP_ITEM_NAME} (vault: ${OP_VAULT})" \
            || log_warn "Could not update 1Password item ${OP_ITEM_NAME}; the git config is written anyway."
    else
        op item create --category="Secure Note" --title="$OP_ITEM_NAME" --vault="$OP_VAULT" \
            --tags="managed:ns-bootstrap" "${fields[@]}" >/dev/null \
            && log_info "Created 1Password item ${OP_ITEM_NAME} (vault: ${OP_VAULT})" \
            || log_warn "Could not create 1Password item ${OP_ITEM_NAME} in vault ${OP_VAULT}; the git config is written anyway."
    fi
fi

# --- What git will now use ---------------------------------------------------
if [[ -f "${HOME}/.gitconfig" ]] && git config --file "${HOME}/.gitconfig" --get user.email >/dev/null 2>&1; then
    log_warn "${HOME}/.gitconfig sets user.email itself, so it wins over the work identity. Check: git config --show-origin user.email"
fi
log_info "Work git identity ready: ${GIT_NAME_WORK} <${GIT_EMAIL_WORK}>, signing: ${WORK_SIGNING}"
