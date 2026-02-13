# my_setup

Cross-platform system bootstrap for macOS (zsh) and Ubuntu 24.04 (bash).

## Quick Start

```bash
git clone https://github.com/ns408/my_setup.git ~/my_setup
cd ~/my_setup
./install/bootstrap.sh                  # Full install (admin)
./install/bootstrap.sh --dotfiles-only  # Dotfiles only (non-admin)
```

## Profiles

| Profile | Includes |
|---------|----------|
| **minimal** | Core CLI tools, modern replacements (ripgrep, fd, fzf, bat, zoxide), browsers, utilities |
| **developer** | Minimal + languages (Python, Go, Ruby), Docker, OrbStack, AWS CLI, dev tools |
| **cloud-engineer** | Developer + Terraform, Azure CLI, Kubernetes, security tools, Wireshark |

## Structure

```
dotfiles/       # Config templates (.gitconfig, .zshrc, starship.toml, etc.)
shell/          # Functions, aliases, platform-specific scripts
packages/       # Brewfiles (macOS) and apt-packages (Ubuntu)
install/        # Bootstrap installer and tool scripts
secrets/        # Secrets management bootstrap
scripts/        # Backup, migration, system maintenance
```

## Secrets

Secrets are managed via 1Password CLI (macOS) or pass (Ubuntu). No secrets are stored in this repo.

```bash
source shell/functions/secrets.sh
get_secret "git/email-personal"
set_secret "github/token" "ghp_..."
```

## Modern CLI Tools

| Traditional | Modern | Description |
|-------------|--------|-------------|
| grep | ripgrep (`rg`) | Faster recursive search |
| find | `fd` | Simpler syntax, respects .gitignore |
| cat | `bat` | Syntax highlighting, line numbers |
| ls | `eza` | Colors, git status, tree view |
| cd | zoxide (`z`) | Jump by frecency |
| top | `btop` | Visual process/resource monitor |
| du | `dust` | Intuitive disk usage |
| diff | `delta` | Side-by-side git diffs |
| dig | `doggo` | DNS with DoH/DoT, colored output |
| curl | `httpie` | Human-friendly HTTP client |
| Ctrl+R | `atuin` | Full-text history search, cross-machine sync |

Run `modern-tools-help` for a full reference.

## Shell

- **Framework:** Oh-My-Zsh (plugins, completions, git aliases)
- **Prompt:** Starship (Rust-based, cross-shell, context-aware)
- **History:** Atuin (SQLite-backed, fuzzy search, encrypted sync)
- **Enhancements:** zsh-autosuggestions, zsh-syntax-highlighting, fzf-tab

## macOS Initial Setup

This section outlines initial setup steps specific to macOS.

### Two-Account Setup

This repo is designed for a two-account macOS workflow:

- **Admin account** — installs Homebrew packages, system updates, and privileged operations
- **Daily account** — non-admin, used for day-to-day development work

Shared files (repositories, data, configs) reside in `/Users/Shared` so both accounts can access them.

**Shared directory permissions** — Run once from the admin account to grant the `staff` group (which both accounts belong to) full read/write access with inheritance:

```bash
sudo chmod -R +a \
  "group:staff allow list,add_file,search,add_subdirectory,delete_child,readattr,writeattr,readextattr,writeextattr,readsecurity,file_inherit,directory_inherit" \
  /Users/Shared/repositories
```

**Bootstrap workflow:**

```bash
# 1. As admin account — full install (packages + dotfiles + secrets)
./install/bootstrap.sh

# 2. As daily account — dotfiles only (symlinks + oh-my-zsh + secrets)
./install/bootstrap.sh --dotfiles-only
```

### Scheduled Updates

Bootstrap installs daily scheduled update agents (launchd on macOS, systemd timers on Ubuntu):

| Schedule | What | Requires |
|----------|------|----------|
| 07:00 daily | `update-brew-daily` — Homebrew formulae only | No interaction |
| 07:30 daily | `update-my-system` — Casks, mise, omz, App Store, softwareupdate | tmux session (admin only) |

**Important:** You must be logged into the respective account via the macOS GUI (not via `su` or SSH) for the interactive update to work correctly. Some tools — notably `mas` (Mac App Store) and `softwareupdate` — require an active Aqua/GUI session. Running from a non-GUI context (e.g. `su - admin_user` from your daily account) may cause password prompts that block indefinitely or silently skip updates.

To run updates manually:

```bash
update-brew-daily    # Quick — formulae only
update-my-system     # Full — casks, mise, omz, softwareupdate list
update-macos-install # Manual — install macOS updates (may reboot)
```

### Hostname Configuration

The `scutil` command is the standard and recommended way to set your Mac's hostname, computer name, and local hostname from the command line.

```bash
# Set your desired hostname
YOUR_HOSTNAME="my-macbook-pro-m2"
sudo scutil --set HostName "$YOUR_HOSTNAME"
sudo scutil --set ComputerName "$YOUR_HOSTNAME"
sudo scutil --set LocalHostName "$YOUR_HOSTNAME"
```

### Essential System & Developer Setup

These steps are commonly performed on a new macOS machine, especially for development.

- **Update macOS:** Ensure your system is running the latest available updates.
  ```bash
  sudo softwareupdate -i -a --restart
  ```
- **Install Xcode Command Line Tools:** Required for many development utilities.
  ```bash
  xcode-select --install
  ```
- **Adjust Trackpad/Mouse Settings:** Personalize tracking speed, tap to click, and natural scrolling.
- **Configure Keyboard Settings:** Set key repeat rate, delay until repeat, and review modifier keys. Consider enabling "Full Keyboard Access" for easier navigation.
- **Finder Preferences:** Enable showing all filename extensions and hidden files (`Cmd+Shift+.` toggles hidden files). Set new Finder windows to open to your Home directory or Downloads.
- **Clear Dock:** Remove default apps from the Dock for a clean start.
  ```bash
  defaults write "com.apple.dock" "persistent-apps" -array && killall Dock
  ```
- **Enable Firewall:** Enhance security by enabling the built-in macOS firewall.
  ```bash
  sudo defaults write /Library/Preferences/com.apple.alf globalstate -int 1
  ```
- **Enable FileVault:** Encrypt your startup disk for data protection (already mentioned, reinforcing).
  ```bash
  sudo fdesetup enable
  ```
- **Disable Homebrew Analytics:** Prevent Homebrew from sending anonymous usage data.
  ```bash
  brew analytics off
  ```

