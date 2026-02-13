# Secrets Management

## Strategy: Abstraction Layer

Provide a unified `get_secret`/`set_secret` interface that auto-detects the available backend:

1. **1Password CLI** (`op`) — primary on macOS
2. **pass** (password-store with GPG) — primary on Linux
3. **macOS Keychain** (`security`) — fallback on macOS
4. **Environment variables** — fallback everywhere

```bash
get_secret() {
    local name="$1"
    if command -v op &>/dev/null; then
        _get_secret_1password "$name"
    elif command -v pass &>/dev/null; then
        _get_secret_pass "$name"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        _get_secret_keychain "$name"
    fi
}
```

## 1Password Structured Items

Instead of creating many separate password items, use a single **Secure Note** with sections:

```
Item: "my_setup" (Secure Note)
├── Git Personal
│   ├── name
│   ├── email
│   └── signing_key
├── Git Work
│   ├── name
│   └── email
├── Tokens
│   └── homebrew_github
└── Network
    └── mac_address
```

Read a specific field: `op read "op://Vault/my_setup/Git Personal/email"`

Tag managed items: `--tags "managed:my_setup"` + notes field explaining the item is auto-managed.

### Structured Item CRUD

```bash
# Create
op item create --category="Secure Note" --title="my_setup" --vault="Personal" \
    "Git Personal.name[text]=John" "Git Personal.email[text]=john@example.com"

# Update
op item edit "my_setup" --vault="Personal" "Git Personal.name[text]=Jane"

# Read
op read "op://Personal/my_setup/Git Personal/name"

# Check existence
op item get "my_setup" --vault="Personal" &>/dev/null
```

## Non-Secret Config

Machine-specific settings that aren't secrets (data directories, tool paths) belong in `~/.config/<app>/config`, not in a secrets manager:

```bash
# ~/.config/my_setup/config
export DATA_DIR="/Users/Shared/data"
export OP_SSH_SIGN_PATH="/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
```

Source this at shell startup — no authentication needed.

## pass (Linux)

```bash
# Initialize
gpg --gen-key
pass init <gpg-key-id>

# Structured paths
pass insert my_setup/git-personal/name
pass show my_setup/git-personal/name
```

## Never Eager-Load Secrets

Do NOT call secret-fetching functions at shell source time. This causes:
- Authentication prompts on every new terminal
- Slow shell startup
- Security prompts users learn to blindly accept

Instead, use explicit functions the user calls when needed:

```bash
# BAD — runs on every shell startup
export TOKEN="$(op read "op://Vault/Item/token")"

# GOOD — user calls when needed
fetch-token() {
    export TOKEN="$(op read "op://Vault/Item/token")"
    echo "Token set for this session"
}
```
