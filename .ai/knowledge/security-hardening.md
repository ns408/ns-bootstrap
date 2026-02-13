# Security Hardening

## Global Git Hooks (gitleaks)

Use `core.hooksPath` to apply hooks to all repositories without per-repo setup:

```bash
mkdir -p ~/.config/git/hooks
git config --global core.hooksPath ~/.config/git/hooks
```

Pre-commit hook for secret scanning:

```bash
#!/usr/bin/env bash
# ~/.config/git/hooks/pre-commit
if ! command -v gitleaks &>/dev/null; then
    exit 0  # Silently skip if not installed
fi
gitleaks protect --staged --no-banner --redact
```

Bypass for a specific commit: `git commit --no-verify`

## npm Security

```ini
# ~/.npmrc
ignore-scripts=true      # Prevent supply chain attacks via postinstall scripts
audit-level=moderate
fund=false
```

Run scripts explicitly when needed: `npm install && npm run build`

## git safe.directory

For shared repositories accessed by multiple users (e.g., `/Users/Shared/`):

```bash
git config --global --add safe.directory /path/to/shared/repo
```

Without this, git refuses to operate in repos owned by a different user.

## .gitignore_global Patterns

Essential patterns for a global gitignore:

```
# Secrets
.env
.env.*
*.pem
*.key

# macOS
.DS_Store
._*

# IDE
.idea/
.vscode/
*.swp
*.swo

# Build artifacts
node_modules/
dist/
coverage/
*.log

# Terraform
.terraform/
*.tfstate
*.tfstate.*

# Direnv
.direnv/
```

## SSH Commit Signing with 1Password

Use 1Password's SSH agent for git commit signing — no need to manage separate GPG keys:

```ini
# .gitconfig
[gpg]
    format = ssh
[gpg "ssh"]
    program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
[commit]
    gpgsign = true
```

Cross-platform: detect `op-ssh-sign` path at bootstrap time:
- macOS: `/Applications/1Password.app/Contents/MacOS/op-ssh-sign`
- Linux: `/opt/1Password/op-ssh-sign`
