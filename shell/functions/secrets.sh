#!/usr/bin/env bash
# Unified Secrets Management Abstraction Layer
# Provides cross-platform secrets retrieval from multiple providers
#
# 1Password storage: Single "ns-bootstrap" secure note with sections
#   Read:  op read "op://Personal/ns-bootstrap/SECTION/FIELD"
#   Item:  op item get "ns-bootstrap" --vault=Personal
#
# pass storage: Structured paths under ns-bootstrap/
#   Read:  pass show "ns-bootstrap/section/field"

# 1Password item configuration (must match bootstrap-secrets.sh)
_OP_ITEM_NAME="ns-bootstrap"
_OP_VAULT="Personal"

# === Main Functions ===

# Get a secret from the appropriate provider
# Usage: get_secret <secret-name> [provider]
# Providers: auto, 1password, pass, keychain, env
get_secret() {
    local secret_name="$1"
    local provider="${2:-auto}"

    case "$provider" in
        auto)
            _get_secret_auto "$secret_name"
            ;;
        1password|op)
            _get_secret_1password "$secret_name"
            ;;
        pass)
            _get_secret_pass "$secret_name"
            ;;
        keychain)
            _get_secret_keychain "$secret_name"
            ;;
        env)
            _get_secret_env "$secret_name"
            ;;
        *)
            echo "Error: Unknown provider '$provider'" >&2
            echo "Valid providers: auto, 1password, pass, keychain, env" >&2
            return 1
            ;;
    esac
}

# Set a secret in the appropriate provider
# Usage: set_secret <secret-name> <secret-value> [provider]
set_secret() {
    local secret_name="$1"
    local secret_value="$2"
    local provider="${3:-auto}"

    case "$provider" in
        auto)
            _set_secret_auto "$secret_name" "$secret_value"
            ;;
        1password|op)
            _set_secret_1password "$secret_name" "$secret_value"
            ;;
        pass)
            _set_secret_pass "$secret_name" "$secret_value"
            ;;
        keychain)
            _set_secret_keychain "$secret_name" "$secret_value"
            ;;
        env)
            echo "Error: Cannot set environment variable secrets. Set manually." >&2
            return 1
            ;;
        *)
            echo "Error: Unknown provider '$provider'" >&2
            return 1
            ;;
    esac
}

# Export a secret as an environment variable
# Usage: export_secret <secret-name> [env-var-name]
export_secret() {
    local secret_name="$1"
    local env_var="${2:-$secret_name}"

    local secret_value
    secret_value=$(get_secret "$secret_name")

    if [[ -n "$secret_value" ]]; then
        export "$env_var"="$secret_value"
        return 0
    else
        echo "Warning: Secret '$secret_name' is empty or not found" >&2
        return 1
    fi
}

# === Auto-Detection ===

_get_secret_auto() {
    local secret_name="$1"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        _get_secret_macos "$secret_name"
    else
        _get_secret_ubuntu "$secret_name"
    fi
}

_set_secret_auto() {
    local secret_name="$1"
    local secret_value="$2"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        _set_secret_macos "$secret_name" "$secret_value"
    else
        _set_secret_ubuntu "$secret_name" "$secret_value"
    fi
}

_get_secret_macos() {
    local secret_name="$1"

    # Try 1Password first if available and signed in
    if command -v op &> /dev/null && op account list &> /dev/null 2>&1; then
        _get_secret_1password "$secret_name" && return 0
    fi

    # Fall back to system keychain
    _get_secret_keychain "$secret_name"
}

_set_secret_macos() {
    local secret_name="$1"
    local secret_value="$2"

    # Prefer 1Password if available
    if command -v op &> /dev/null && op account list &> /dev/null 2>&1; then
        _set_secret_1password "$secret_name" "$secret_value"
    else
        _set_secret_keychain "$secret_name" "$secret_value"
    fi
}

_get_secret_ubuntu() {
    local secret_name="$1"

    # Use pass (password-store)
    if command -v pass &> /dev/null; then
        _get_secret_pass "$secret_name"
    else
        echo "Error: password-store not found. Install: sudo apt install pass" >&2
        echo "Then initialize: pass init <gpg-key-id>" >&2
        return 1
    fi
}

_set_secret_ubuntu() {
    local secret_name="$1"
    local secret_value="$2"

    if command -v pass &> /dev/null; then
        _set_secret_pass "$secret_name" "$secret_value"
    else
        echo "Error: password-store not found" >&2
        return 1
    fi
}

# === Provider Implementations ===

# 1Password CLI — structured item with sections
_get_secret_1password() {
    local secret_name="$1"
    local secret_value

    # Try structured item first (op://vault/ns-bootstrap/section/field)
    # Map common secret names to structured paths
    local op_path
    op_path=$(_map_secret_to_op_path "$secret_name")
    if [[ -n "$op_path" ]]; then
        secret_value=$(op read "$op_path" 2>/dev/null) && echo "$secret_value" && return 0
    fi

    # Fallback: try as direct op:// reference
    secret_value=$(op read "op://${_OP_VAULT}/$secret_name" 2>/dev/null) && echo "$secret_value" && return 0

    # Fallback: try as standalone item (backward compat with old flat items)
    secret_value=$(op item get "$secret_name" --fields password 2>/dev/null) && echo "$secret_value" && return 0

    return 1
}

# Map flat secret names to structured op:// paths
_map_secret_to_op_path() {
    local name="$1"
    local base="op://${_OP_VAULT}/${_OP_ITEM_NAME}"

    case "$name" in
        git/name-personal)          echo "${base}/Git Personal/name" ;;
        git/email-personal)         echo "${base}/Git Personal/email" ;;
        git/signing-key)            echo "${base}/Git Personal/signing_key" ;;
        git/name-work)              echo "${base}/Git Work/name" ;;
        git/email-work)             echo "${base}/Git Work/email" ;;
        git/work-signing-key)       echo "${base}/Git Work/signing_key" ;;
        git/work-repo-dir)          echo "${base}/Git Work/repo_dir" ;;
        homebrew/github-token)      echo "${base}/Tokens/homebrew_github" ;;
        network/*)                  echo "${base}/Network/backup_password" ;;
        *)                          echo "" ;;
    esac
}

_set_secret_1password() {
    local secret_name="$1"
    local secret_value="$2"

    # Map to structured field if known
    local section_field
    case "$secret_name" in
        git/name-personal)          section_field="Git Personal.name[text]" ;;
        git/email-personal)         section_field="Git Personal.email[text]" ;;
        git/signing-key)            section_field="Git Personal.signing_key[text]" ;;
        git/name-work)              section_field="Git Work.name[text]" ;;
        git/email-work)             section_field="Git Work.email[text]" ;;
        git/work-signing-key)       section_field="Git Work.signing_key[text]" ;;
        git/work-repo-dir)          section_field="Git Work.repo_dir[text]" ;;
        homebrew/github-token)      section_field="Tokens.homebrew_github[password]" ;;
        network/*)                  section_field="Network.backup_password[password]" ;;
        *)                          section_field="" ;;
    esac

    if [[ -n "$section_field" ]]; then
        # Add/update field on the structured item
        if op item get "$_OP_ITEM_NAME" --vault="$_OP_VAULT" &>/dev/null; then
            op item edit "$_OP_ITEM_NAME" \
                --vault="$_OP_VAULT" \
                "${section_field}=${secret_value}" \
                >/dev/null 2>/dev/null
        else
            # Item doesn't exist yet — create it
            op item create \
                --category="Secure Note" \
                --title="$_OP_ITEM_NAME" \
                --vault="$_OP_VAULT" \
                --tags="managed:ns-bootstrap" \
                "${section_field}=${secret_value}" \
                "notesPlain=Managed by ns-bootstrap bootstrap-secrets.sh." \
                >/dev/null 2>/dev/null
        fi
    else
        # Unknown secret — create as standalone item (fallback)
        op item create \
            --category=password \
            --title="$secret_name" \
            --vault="$_OP_VAULT" \
            password="$secret_value" \
            >/dev/null 2>/dev/null
    fi
}

# pass (password-store) — structured paths under ns-bootstrap/
_get_secret_pass() {
    local secret_name="$1"
    local pass_path

    # Try structured path first
    pass_path=$(_map_secret_to_pass_path "$secret_name")
    if [[ -n "$pass_path" ]]; then
        pass show "$pass_path" 2>/dev/null | head -n1 && return 0
    fi

    # Fallback: try as-is
    pass show "$secret_name" 2>/dev/null | head -n1
}

_set_secret_pass() {
    local secret_name="$1"
    local secret_value="$2"
    local pass_path

    # Use structured path if known
    pass_path=$(_map_secret_to_pass_path "$secret_name")
    echo "$secret_value" | pass insert -m "${pass_path:-$secret_name}" 2>/dev/null
}

# Map flat secret names to pass paths
_map_secret_to_pass_path() {
    local name="$1"
    case "$name" in
        git/name-personal)          echo "ns-bootstrap/git-personal/name" ;;
        git/email-personal)         echo "ns-bootstrap/git-personal/email" ;;
        git/signing-key)            echo "ns-bootstrap/git-personal/signing-key" ;;
        git/name-work)              echo "ns-bootstrap/git-work/name" ;;
        git/email-work)             echo "ns-bootstrap/git-work/email" ;;
        git/work-signing-key)       echo "ns-bootstrap/git-work/signing-key" ;;
        git/work-repo-dir)          echo "ns-bootstrap/git-work/repo-dir" ;;
        homebrew/github-token)      echo "ns-bootstrap/tokens/homebrew-github" ;;
        network/*)                  echo "ns-bootstrap/network/backup-password" ;;
        *)                          echo "" ;;
    esac
}

# macOS Keychain
_get_secret_keychain() {
    local secret_name="$1"

    # Try generic password first (most common)
    security find-generic-password -a "$secret_name" -w 2>/dev/null && return 0

    # Try internet password (for network credentials)
    security find-internet-password -l "$secret_name" -w 2>/dev/null && return 0

    # Try with service name
    security find-generic-password -s "$secret_name" -w 2>/dev/null && return 0

    return 1
}

_set_secret_keychain() {
    local secret_name="$1"
    local secret_value="$2"

    # Add to keychain (generic password)
    security add-generic-password \
        -a "$secret_name" \
        -s "$secret_name" \
        -w "$secret_value" \
        -U \
        2>/dev/null
}

# Environment Variable
_get_secret_env() {
    local secret_name="$1"
    printenv "$secret_name"
}

# === Helper Functions ===

# Check if secrets manager is available
secrets_available() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # On macOS, check for 1Password or keychain
        if command -v op &> /dev/null && op account list &> /dev/null 2>&1; then
            echo "1password"
            return 0
        elif command -v security &> /dev/null; then
            echo "keychain"
            return 0
        fi
    else
        # On Ubuntu, check for pass
        if command -v pass &> /dev/null; then
            echo "pass"
            return 0
        fi
    fi

    echo "none"
    return 1
}

# List all secrets (if provider supports it)
secrets_list() {
    local provider="${1:-auto}"

    case "$provider" in
        auto)
            local available
            available=$(secrets_available)
            secrets_list "$available"
            ;;
        1password|op)
            op item list --format=json 2>/dev/null | jq -r '.[].title'
            ;;
        pass)
            pass ls
            ;;
        keychain)
            echo "Keychain listing not supported (security limitation)"
            return 1
            ;;
        *)
            echo "Error: Unknown provider '$provider'" >&2
            return 1
            ;;
    esac
}

# Interactive secret selection
secrets_select() {
    if ! command -v fzf &> /dev/null; then
        echo "Error: fzf not found. Install for interactive selection." >&2
        return 1
    fi

    local provider
    provider=$(secrets_available)

    if [[ "$provider" == "none" ]]; then
        echo "Error: No secrets manager available" >&2
        return 1
    fi

    local selected
    selected=$(secrets_list "$provider" | fzf --prompt="Select secret: ")

    if [[ -n "$selected" ]]; then
        get_secret "$selected" "$provider"
    fi
}

# === Convenience Wrappers ===

# Common secrets shortcuts
get_github_token() {
    get_secret "github/personal-access-token" 2>/dev/null || \
    printenv GITHUB_TOKEN 2>/dev/null || \
    echo ""
}

get_aws_access_key() {
    get_secret "aws/access-key-id" 2>/dev/null || \
    printenv AWS_ACCESS_KEY_ID 2>/dev/null || \
    echo ""
}

get_aws_secret_key() {
    get_secret "aws/secret-access-key" 2>/dev/null || \
    printenv AWS_SECRET_ACCESS_KEY 2>/dev/null || \
    echo ""
}

get_homebrew_token() {
    get_secret "homebrew/github-token" 2>/dev/null || \
    printenv HOMEBREW_GITHUB_API_TOKEN 2>/dev/null || \
    echo ""
}

# Export all AWS credentials
export_aws_credentials() {
    export_secret "aws/access-key-id" "AWS_ACCESS_KEY_ID"
    export_secret "aws/secret-access-key" "AWS_SECRET_ACCESS_KEY"

    # Optional: region and profile
    export_secret "aws/region" "AWS_DEFAULT_REGION" 2>/dev/null || true
    export_secret "aws/profile" "AWS_PROFILE" 2>/dev/null || true
}

# === Usage Examples ===
#
# Basic usage:
#   get_secret "homebrew/github-token"
#   get_secret "GITHUB_TOKEN" env
#
# Set secrets:
#   set_secret "api-key" "my-secret-value"
#   echo "my-secret" | set_secret "password"
#
# Export to environment:
#   export_secret "github/token" "GITHUB_TOKEN"
#
# Interactive selection:
#   secret=$(secrets_select)
#
# Check availability:
#   secrets_available  # Returns: 1password, pass, keychain, or none
#
# List secrets:
#   secrets_list
#
