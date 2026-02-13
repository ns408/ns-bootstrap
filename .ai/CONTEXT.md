# Project Context — ns-bootstrap

This is a cross-platform system bootstrap for macOS and Ubuntu 24.04.
It manages dotfiles, shell configuration, package installation, and secrets.

## Key Conventions

- Shell scripts target zsh (macOS) and bash (Ubuntu)
- Secrets are managed via 1Password CLI (macOS) or pass (Ubuntu) — never committed
- Config files use `${PLACEHOLDER}` template variables processed by `secrets/bootstrap-secrets.sh`
- Brewfiles are split by profile: minimal, developer, cloud-engineer
- Modern CLI replacements are preferred (ripgrep, fd, bat, eza, zoxide, atuin)

## Structure

```
dotfiles/       # Config templates (.gitconfig, .zshrc, starship.toml)
shell/          # Functions, aliases, platform-specific scripts
packages/       # Brewfiles (macOS) and apt-packages (Ubuntu)
install/        # Bootstrap installer and tool scripts
secrets/        # Secrets management bootstrap
scripts/        # Backup, migration, system maintenance
```
