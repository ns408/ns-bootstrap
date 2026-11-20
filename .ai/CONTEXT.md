# Project Context — ns-bootstrap

This is a cross-platform system bootstrap for macOS and Ubuntu 24.04.
It manages dotfiles, shell configuration, package installation, and secrets.

## Key Conventions

- Shell scripts target zsh on both macOS and Ubuntu
- Secrets are managed via 1Password CLI (macOS) or pass (Ubuntu) — never committed
- Config files use `${PLACEHOLDER}` template variables processed by `secrets/bootstrap-secrets.sh`
- Brewfiles are split by profile: minimal, developer, cloud-engineer, and work (a company-managed Mac; open-source formulae only, keeps the company's files: see README "Work Profile")
- Settings: environment, then `~/.config/ns-bootstrap/settings`, then the profile default; all listed in `docs/settings.md`
- Modern CLI replacements are preferred (ripgrep, fd, bat, eza, zoxide, atuin)

## Structure

```
dotfiles/       # Config templates (.gitconfig, .zshrc, starship.toml)
shell/          # Functions, aliases, platform-specific scripts
packages/       # Brewfiles (macOS) and apt-packages (Ubuntu)
install/        # Bootstrap installer and tool scripts
secrets/        # Secrets management bootstrap
scripts/        # Scheduled update script, launchd templates, pin bumps, git hooks
```
