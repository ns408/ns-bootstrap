#!/usr/bin/env bash
# Secrets Management Bootstrap Script
# Initializes secrets system and processes template files
#
# Storage strategy:
#   1Password: Single "ns-bootstrap" secure note with sections (Git Personal, Git Work, Tokens, Network)
#   Config:    ~/.config/ns-bootstrap/config for non-secret machine-specific settings
#   Templates: dotfiles/git/*.template → ~/.gitconfig, ~/.gitconfig-work
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Detect project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 1Password item configuration
OP_ITEM_NAME="ns-bootstrap"
OP_VAULT="Personal"
OP_TAG="managed:ns-bootstrap"

echo "=== Secrets Management Bootstrap ==="
echo ""

# Source secrets functions
if [[ -f "${PROJECT_ROOT}/shell/functions/secrets.sh" ]]; then
    source "${PROJECT_ROOT}/shell/functions/secrets.sh"
else
    log_error "secrets.sh not found at: ${PROJECT_ROOT}/shell/functions/secrets.sh"
    exit 1
fi

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
elif [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "$ID" == "ubuntu" ]]; then
        OS="ubuntu"
    else
        log_error "Unsupported Linux distribution: $ID"
        exit 1
    fi
else
    log_error "Unsupported operating system"
    exit 1
fi

log_info "Detected OS: $OS"

# Detect op-ssh-sign path for SSH commit signing
if [[ "$OS" == "macos" ]]; then
    OP_SSH_SIGN_DEFAULT="/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
else
    OP_SSH_SIGN_DEFAULT="/opt/1Password/op-ssh-sign"
fi

if [[ -f "$OP_SSH_SIGN_DEFAULT" ]]; then
    OP_SSH_SIGN_PATH="$OP_SSH_SIGN_DEFAULT"
    log_info "Found op-ssh-sign: $OP_SSH_SIGN_PATH"
elif command -v op-ssh-sign &>/dev/null; then
    OP_SSH_SIGN_PATH="$(command -v op-ssh-sign)"
    log_info "Found op-ssh-sign in PATH: $OP_SSH_SIGN_PATH"
else
    log_warn "op-ssh-sign not found. SSH commit signing will not work."
    log_warn "Install 1Password and enable SSH agent integration."
    OP_SSH_SIGN_PATH=""
fi

# Set git credential helper based on OS
if [[ "$OS" == "macos" ]]; then
    GIT_CREDENTIAL_HELPER="osxkeychain"
else
    GIT_CREDENTIAL_HELPER="store"
fi

echo ""

# === Step 1: Install Secrets Provider ===
log_step "Step 1: Installing secrets provider..."

if [[ "$OS" == "macos" ]]; then
    log_info "Checking for 1Password CLI..."
    if ! command -v op &> /dev/null; then
        if dseditgroup -o checkmember -m "$(whoami)" admin &>/dev/null && command -v brew &> /dev/null; then
            log_warn "1Password CLI not found. Installing via Homebrew..."
            brew install --cask 1password-cli
        else
            log_error "1Password CLI not found. Install it from the admin account first."
            exit 1
        fi
    else
        log_info "1Password CLI already installed: $(op --version)"
    fi

    # Check if signed in
    if ! op account list &> /dev/null 2>&1; then
        log_warn "Not signed in to 1Password. Please sign in:"
        eval "$(op signin)"
    else
        log_info "Already signed in to 1Password"
    fi

    PROVIDER="1password"

else
    log_info "Checking for pass (password-store)..."
    if ! command -v pass &> /dev/null; then
        log_warn "pass not found. Installing..."
        sudo apt update
        sudo apt install -y pass gnupg2

        log_info "pass installed. You need to initialize it with a GPG key."
        echo "Steps:"
        echo "  1. Generate GPG key: gpg --full-generate-key"
        echo "  2. List keys: gpg --list-keys"
        echo "  3. Initialize pass: pass init <your-gpg-key-id>"
        echo ""
        read -p "Press Enter after completing these steps..."
    else
        log_info "pass already installed"
    fi

    PROVIDER="pass"
fi

echo ""

# === Step 2: Collect Values ===
log_step "Step 2: Collecting configuration values..."

# Helper: prompt user for a value, showing existing if available
prompt_value() {
    local prompt_message="$1"
    local existing_value="${2:-}"

    if [[ -n "$existing_value" ]]; then
        log_info "  Current: $existing_value" >&2
        read -p "  $prompt_message [$existing_value]: " new_value </dev/tty
        echo "${new_value:-$existing_value}"
    else
        read -p "  $prompt_message: " new_value </dev/tty
        echo "$new_value"
    fi
}

# Helper: require a non-empty value
require_value() {
    local value="$1"
    local field_name="$2"
    if [[ -z "$value" ]]; then
        log_error "${field_name} cannot be empty"
        exit 1
    fi
}

# Try to read existing values from 1Password structured item
_read_existing_op_field() {
    local section="$1"
    local field="$2"
    if [[ "$PROVIDER" == "1password" ]]; then
        local op_full_path="op://${OP_VAULT}/${OP_ITEM_NAME}/${section}/${field}"
        log_info "  Attempting to fetch '$field' from 1Password (path: $op_full_path)..." >&2
        local value
        value=$(op read "$op_full_path" 2>/dev/null)
        echo "$value"
    else
        echo ""
    fi
}

# --- Git Personal ---
log_info "Git personal configuration..."
existing_name=$(_read_existing_op_field "Git Personal" "name")
existing_email=$(_read_existing_op_field "Git Personal" "email")
existing_signing_key=$(_read_existing_op_field "Git Personal" "signing_key")

GIT_NAME_PERSONAL=$(prompt_value "Personal git name (e.g., John Doe)" "$existing_name")
require_value "$GIT_NAME_PERSONAL" "Git name"

GIT_EMAIL_PERSONAL=$(prompt_value "Personal git email" "$existing_email")
require_value "$GIT_EMAIL_PERSONAL" "Git email"

GIT_SIGNING_KEY=$(prompt_value "SSH signing key (e.g., ssh-ed25519 AAAA...)" "$existing_signing_key")
if [[ -n "$GIT_SIGNING_KEY" ]] && [[ "$GIT_SIGNING_KEY" != ssh-* ]] && [[ "$GIT_SIGNING_KEY" != ecdsa-* ]]; then
    log_warn "Signing key doesn't look like an SSH key (expected ssh-ed25519/ssh-rsa/ecdsa-sha2)."
    log_warn "If using GPG, set gpg.format to 'openpgp' in your .gitconfig manually."
fi

# --- Git Work (optional) ---
echo ""
read -p "Do you have work git credentials? (y/n): " has_work
if [[ "$has_work" == "y" ]]; then
    log_info "Git work configuration..."
    existing_work_name=$(_read_existing_op_field "Git Work" "name")
    existing_work_email=$(_read_existing_op_field "Git Work" "email")
    existing_work_repo=$(_read_existing_op_field "Git Work" "repo_dir")

    GIT_NAME_WORK=$(prompt_value "Work git name" "$existing_work_name")
    require_value "$GIT_NAME_WORK" "Work git name"

    GIT_EMAIL_WORK=$(prompt_value "Work git email" "$existing_work_email")
    require_value "$GIT_EMAIL_WORK" "Work git email"

    WORK_REPO_DIR=$(prompt_value "Work repository directory (e.g., /shared/clients/repositories/)" "$existing_work_repo")
    require_value "$WORK_REPO_DIR" "Work repo directory"

    # Ensure trailing slash for gitdir matching
    [[ "$WORK_REPO_DIR" != */ ]] && WORK_REPO_DIR="${WORK_REPO_DIR}/"

    if [[ ! -d "$WORK_REPO_DIR" ]]; then
        log_warn "Directory does not exist yet: ${WORK_REPO_DIR}"
        log_warn "The includeIf will activate once you create it."
    fi

    echo ""
    read -p "Does your work use GPG signing? (y/n, default: n = SSH via 1Password): " work_gpg
    if [[ "${work_gpg:-n}" == "y" ]]; then
        existing_work_key=$(_read_existing_op_field "Git Work" "signing_key")
        WORK_SIGNING_KEY=$(prompt_value "Work GPG signing key ID" "$existing_work_key")
        require_value "$WORK_SIGNING_KEY" "Work signing key"
        WORK_GPG_SECTION=$'[gpg]\n    format = openpgp'
    else
        WORK_SIGNING_KEY="${GIT_SIGNING_KEY}"
        WORK_GPG_SECTION=""
    fi
fi

# --- Network (optional) ---
echo ""
read -p "Do you need network backup credentials? (y/n): " has_network
if [[ "$has_network" == "y" ]]; then
    existing_network=$(_read_existing_op_field "Network" "backup_password")
    NETWORK_PASSWORD=$(prompt_value "Network backup password" "$existing_network")
fi

# --- System config (non-secret, stored locally) ---
echo ""
log_info "System configuration (stored locally, not in 1Password)..."
read -p "  Shared data directory path [/Users/Shared]: " data_dir_input </dev/tty
DATA_DIR="${data_dir_input:-/Users/Shared}"

read -p "  MAC address to store for reset (leave blank to skip): " mac_address_input </dev/tty
MAC_ADDRESS="${mac_address_input:-}"

echo ""

# === Step 3: Store Secrets ===
log_step "Step 3: Storing secrets..."

if [[ "$PROVIDER" == "1password" ]]; then
    # Build field arguments for op item create/edit
    OP_FIELDS=()
    OP_FIELDS+=("Git Personal.name[text]=${GIT_NAME_PERSONAL}")
    OP_FIELDS+=("Git Personal.email[text]=${GIT_EMAIL_PERSONAL}")
    [[ -n "${GIT_SIGNING_KEY:-}" ]] && OP_FIELDS+=("Git Personal.signing_key[text]=${GIT_SIGNING_KEY}")

    if [[ "${has_work:-n}" == "y" ]]; then
        OP_FIELDS+=("Git Work.name[text]=${GIT_NAME_WORK}")
        OP_FIELDS+=("Git Work.email[text]=${GIT_EMAIL_WORK}")
        OP_FIELDS+=("Git Work.repo_dir[text]=${WORK_REPO_DIR}")
        [[ -n "${WORK_SIGNING_KEY:-}" ]] && OP_FIELDS+=("Git Work.signing_key[text]=${WORK_SIGNING_KEY}")
    fi

    [[ -n "${NETWORK_PASSWORD:-}" ]] && OP_FIELDS+=("Network.backup_password[password]=${NETWORK_PASSWORD}")

    # Check if item already exists
    if op item get "$OP_ITEM_NAME" --vault="$OP_VAULT" &>/dev/null; then
        log_info "Updating existing 1Password item: $OP_ITEM_NAME"
        op item edit "$OP_ITEM_NAME" \
            --vault="$OP_VAULT" \
            "${OP_FIELDS[@]}" \
            >/dev/null
    else
        log_info "Creating 1Password item: $OP_ITEM_NAME"
        op item create \
            --category="Secure Note" \
            --title="$OP_ITEM_NAME" \
            --vault="$OP_VAULT" \
            --tags="$OP_TAG" \
            "${OP_FIELDS[@]}" \
            "notesPlain=Managed by ns-bootstrap bootstrap-secrets.sh. Do not modify manually — re-run secrets/bootstrap-secrets.sh to update." \
            >/dev/null
    fi
    log_info "1Password item stored: $OP_ITEM_NAME (vault: $OP_VAULT)"

elif [[ "$PROVIDER" == "pass" ]]; then
    # For pass, store as structured paths
    _pass_store() {
        local path="$1" value="$2"
        echo "$value" | pass insert -m "$path" 2>/dev/null
    }
    _pass_store "ns-bootstrap/git-personal/name" "$GIT_NAME_PERSONAL"
    _pass_store "ns-bootstrap/git-personal/email" "$GIT_EMAIL_PERSONAL"
    [[ -n "${GIT_SIGNING_KEY:-}" ]] && _pass_store "ns-bootstrap/git-personal/signing-key" "$GIT_SIGNING_KEY"

    if [[ "${has_work:-n}" == "y" ]]; then
        _pass_store "ns-bootstrap/git-work/name" "$GIT_NAME_WORK"
        _pass_store "ns-bootstrap/git-work/email" "$GIT_EMAIL_WORK"
        _pass_store "ns-bootstrap/git-work/repo-dir" "$WORK_REPO_DIR"
        [[ -n "${WORK_SIGNING_KEY:-}" ]] && _pass_store "ns-bootstrap/git-work/signing-key" "$WORK_SIGNING_KEY"
    fi

    [[ -n "${NETWORK_PASSWORD:-}" ]] && _pass_store "ns-bootstrap/network/backup-password" "$NETWORK_PASSWORD"
    log_info "Secrets stored in pass under ns-bootstrap/"
fi

# === Step 4: Write local config file ===
log_step "Step 4: Writing local config..."

CONFIG_DIR="${HOME}/.config/ns-bootstrap"
CONFIG_FILE="${CONFIG_DIR}/config"
mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_FILE" << EOF
# ns-bootstrap — Machine-specific settings (non-secret)
# Generated by secrets/bootstrap-secrets.sh on $(date +%Y-%m-%d)
# Edit freely — re-running bootstrap-secrets.sh will overwrite this file

DATA_DIR="${DATA_DIR}"
OP_SSH_SIGN_PATH="${OP_SSH_SIGN_PATH}"
GIT_CREDENTIAL_HELPER="${GIT_CREDENTIAL_HELPER}"
EOF

if [[ -n "$MAC_ADDRESS" ]]; then
    echo "MAC_ADDRESS=\"${MAC_ADDRESS}\"" >> "$CONFIG_FILE"
fi

log_info "Written: $CONFIG_FILE"

# === Step 5: Process Template Files ===
log_step "Step 5: Processing template files..."

# Function to process a template file
process_template() {
    local template_file="$1"
    local output_file="$2"

    if [[ ! -f "$template_file" ]]; then
        log_warn "Template file not found: $template_file"
        return 1
    fi

    log_info "Processing: $template_file -> $output_file"

    # Read template
    local content
    content=$(<"$template_file")

    # Replace placeholders
    content="${content//\$\{GIT_NAME_PERSONAL\}/${GIT_NAME_PERSONAL:-}}"
    content="${content//\$\{GIT_EMAIL_PERSONAL\}/${GIT_EMAIL_PERSONAL:-}}"
    content="${content//\$\{GIT_NAME_WORK\}/${GIT_NAME_WORK:-}}"
    content="${content//\$\{GIT_EMAIL_WORK\}/${GIT_EMAIL_WORK:-}}"
    content="${content//\$\{GIT_SIGNING_KEY\}/${GIT_SIGNING_KEY:-}}"
    content="${content//\$\{WORK_SIGNING_KEY\}/${WORK_SIGNING_KEY:-}}"
    content="${content//\$\{WORK_GPG_SECTION\}/${WORK_GPG_SECTION:-}}"
    content="${content//\$\{WORK_REPO_DIR\}/${WORK_REPO_DIR:-}}"
    content="${content//\$\{OP_SSH_SIGN_PATH\}/${OP_SSH_SIGN_PATH:-}}"
    content="${content//\$\{GIT_CREDENTIAL_HELPER\}/${GIT_CREDENTIAL_HELPER:-store}}"
    content="${content//\$\{DATA_DIR\}/${DATA_DIR:-/Users/Shared}}"
    content="${content//\$\{HOME\}/$HOME}"

    # Create output directory if needed
    mkdir -p "$(dirname "$output_file")"

    # Backup existing file before overwriting
    if [[ -f "$output_file" ]] && [[ ! -L "$output_file" ]]; then
        local backup_dir
        backup_dir="${HOME}/.dotfiles-backup/$(date +%Y%m%d%H%M%S)"
        mkdir -p "$backup_dir"
        local backup_name
        backup_name=$(basename "$output_file")
        cp "$output_file" "${backup_dir}/${backup_name}"
        log_info "Backed up: ${output_file} -> ${backup_dir}/${backup_name}"
    fi

    # Write output file
    printf '%s\n' "$content" > "$output_file"

    log_info "Created: $output_file"
}

# Process .gitconfig
process_template \
    "${PROJECT_ROOT}/dotfiles/git/.gitconfig.template" \
    "${HOME}/.gitconfig"

# Process .gitconfig-work if work credentials provided
if [[ -n "${GIT_NAME_WORK:-}" ]]; then
    process_template \
        "${PROJECT_ROOT}/dotfiles/git/.gitconfig-work.template" \
        "${HOME}/.gitconfig-work"
fi

echo ""

# === Step 6: Verification ===
log_step "Step 6: Verifying installation..."

# Test secret retrieval from structured item
if [[ "$PROVIDER" == "1password" ]]; then
    log_info "Testing 1Password item retrieval..."
    test_val=$(op read "op://${OP_VAULT}/${OP_ITEM_NAME}/Git Personal/name" 2>/dev/null || echo "")
    if [[ -n "$test_val" ]]; then
        log_info "  ✓ 1Password item '$OP_ITEM_NAME' readable"
    else
        log_warn "  ⚠ Could not read from 1Password item"
    fi
elif [[ "$PROVIDER" == "pass" ]]; then
    log_info "Testing pass retrieval..."
    test_val=$(pass show "ns-bootstrap/git-personal/name" 2>/dev/null | head -n1 || echo "")
    if [[ -n "$test_val" ]]; then
        log_info "  ✓ pass secrets readable"
    else
        log_warn "  ⚠ Could not read from pass"
    fi
fi

# Check config file
if [[ -f "$CONFIG_FILE" ]]; then
    log_info "  ✓ Config: $CONFIG_FILE"
else
    log_warn "  ⚠ Config file not found"
fi

# Check generated files
[[ -f "${HOME}/.gitconfig" ]] && log_info "  ✓ ~/.gitconfig" || log_warn "  ⚠ ~/.gitconfig not found"
[[ -f "${HOME}/.gitconfig-work" ]] && log_info "  ✓ ~/.gitconfig-work"

echo ""

# === Summary ===
log_info "=== Bootstrap Complete ==="
echo ""
echo "Provider: $PROVIDER"

if [[ "$PROVIDER" == "1password" ]]; then
    echo ""
    echo "1Password item: '$OP_ITEM_NAME' (vault: $OP_VAULT, tag: $OP_TAG)"
    echo "  Sections:"
    echo "    Git Personal  — name, email, signing_key"
    [[ "${has_work:-n}" == "y" ]] && echo "    Git Work      — name, email, signing_key, repo_dir"
    [[ -n "${NETWORK_PASSWORD:-}" ]] && echo "    Network       — backup_password"
elif [[ "$PROVIDER" == "pass" ]]; then
    echo ""
    echo "pass store: ns-bootstrap/"
    echo "    git-personal/ — name, email, signing-key"
    [[ "${has_work:-n}" == "y" ]] && echo "    git-work/     — name, email, signing-key, repo-dir"
    [[ -n "${NETWORK_PASSWORD:-}" ]] && echo "    network/      — backup-password"
fi

echo ""
echo "Local config: $CONFIG_FILE"
echo "    DATA_DIR, OP_SSH_SIGN_PATH, GIT_CREDENTIAL_HELPER"
[[ -n "$MAC_ADDRESS" ]] && echo "    MAC_ADDRESS"

echo ""
echo "Files created:"
echo "  • ~/.gitconfig"
[[ -f "${HOME}/.gitconfig-work" ]] && echo "  • ~/.gitconfig-work"
echo "  • $CONFIG_FILE"
echo ""
echo "Next steps:"
echo "  1. Test git configuration: git config --get user.name"
echo "  2. Open a new terminal to load config"
echo "  3. Read secrets: op read \"op://${OP_VAULT}/${OP_ITEM_NAME}/Git Personal/name\""
echo ""
