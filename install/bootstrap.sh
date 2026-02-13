#!/usr/bin/env bash
# Main Bootstrap Installer for my_setup
# Supports macOS (zsh) and Ubuntu 24.04 (bash)
#
# Usage:
#   ./bootstrap.sh                  # Full install (admin): packages + dotfiles + secrets
#   ./bootstrap.sh --dotfiles-only  # Dotfiles only (non-admin): symlinks + oh-my-zsh + secrets
#   ./bootstrap.sh --dry-run        # Preview what would be installed (no changes)
set -euo pipefail

# Detect project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Parse flags
DOTFILES_ONLY=false
DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        --dotfiles-only) DOTFILES_ONLY=true ;;
        --dry-run) DRY_RUN=true ;;
        --help|-h)
            echo "Usage: $0 [--dotfiles-only] [--dry-run]"
            echo ""
            echo "  --dotfiles-only  Skip package installation (for non-admin accounts)"
            echo "  --dry-run        Preview what would be installed (no changes made)"
            exit 0
            ;;
    esac
done

# Source shared library
source "${SCRIPT_DIR}/lib/common.sh"

echo ""
echo -e "${BOLD}╔═══════════════════════════════════════╗${NC}"
if [[ "$DOTFILES_ONLY" == true ]]; then
    echo -e "${BOLD}║   my_setup - Dotfiles Bootstrap       ║${NC}"
else
    echo -e "${BOLD}║     my_setup - System Bootstrap       ║${NC}"
fi
echo -e "${BOLD}╚═══════════════════════════════════════╝${NC}"
echo ""

# === Step 1: Detect OS ===
log_step "Step 1: Detecting operating system..."
detect_os
log_info "Detected: ${OS} (${PKG_MGR})"

if [[ "$DOTFILES_ONLY" == false ]]; then
    [[ "$OS" == "macos" ]] && check_brew_permissions

    # === Step 2: Select Profile ===
    log_step "Step 2: Select installation profile"
    echo ""
    echo "  1) minimal        - Essential tools (git, vim, tmux, modern CLI tools)"
    echo "  2) developer       - Minimal + programming languages (Python, Node, Ruby, Go)"
    echo "  3) cloud-engineer  - Developer + cloud tools (AWS, Terraform, Docker, K8s)"
    echo ""
    read -p "Select profile [1-3] (default: 1): " profile_choice

    case "${profile_choice:-1}" in
        1) PROFILE="minimal" ;;
        2) PROFILE="developer" ;;
        3) PROFILE="cloud-engineer" ;;
        *) PROFILE="minimal" ;;
    esac

    log_info "Selected profile: ${PROFILE}"

    # === Dry Run Preview ===
    if [[ "$DRY_RUN" == true ]]; then
        echo ""
        echo -e "${BOLD}=== Dry Run Preview ===${NC}"
        echo ""
        echo "OS:       ${OS} (${PKG_MGR})"
        echo "Profile:  ${PROFILE}"
        echo ""
        echo "Would install:"
        if [[ "$OS" == "macos" ]]; then
            BREWFILE="${PROJECT_ROOT}/packages/Brewfile.${PROFILE}"
            [[ -f "$BREWFILE" ]] && echo "  Brewfile: ${BREWFILE} ($(grep -cE '^(brew|cask|mas) ' "$BREWFILE") packages)"
        else
            APT_FILE="${PROJECT_ROOT}/packages/apt-packages.${PROFILE}"
            [[ -f "$APT_FILE" ]] && echo "  apt packages: ${APT_FILE} ($(wc -l < "$APT_FILE") packages)"
        fi
        echo "  Modern CLI tools via install-modern-tools.sh"
        echo ""
        echo "Would symlink:"
        for f in .zshrc .zprofile .vimrc .inputrc .gitignore_global .tmux.conf .config/starship.toml .npmrc .config/atuin/config.toml; do
            src="${PROJECT_ROOT}/dotfiles"
            echo "  ~/${f}"
        done
        echo ""
        echo "Would configure:"
        echo "  oh-my-zsh + custom plugins"
        echo "  Secrets system (1Password / pass)"
        echo "  Scheduled update agents (launchd / systemd)"
        echo "  Global git hooks (gitleaks pre-commit)"
        echo ""
        echo -e "${GREEN}No changes were made.${NC}"
        exit 0
    fi

    # === Step 3: Confirm ===
    echo ""
    echo -e "${YELLOW}This will:${NC}"
    echo "  - Install ${PROFILE} packages via ${PKG_MGR}"
    echo "  - Install modern CLI tools (ripgrep, fd, fzf, bat, zoxide, etc.)"
    echo "  - Symlink dotfiles (with backup of existing)"
    echo "  - Initialize secrets system"
    echo ""
    read -p "Continue? [y/N]: " confirm
    [[ "${confirm:-n}" != "y" ]] && { echo "Aborted."; exit 0; }

    # === Step 4: Install Package Manager ===
    log_step "Step 3: Ensuring package manager is available..."

    if [[ "$OS" == "macos" ]]; then
        if ! command -v brew &>/dev/null; then
            log_info "Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

            # Add to PATH for current session
            if [ "$(arch)" = "arm64" ]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            else
                eval "$(/usr/local/bin/brew shellenv)"
            fi
        else
            log_info "Homebrew already installed"
        fi
    else
        log_info "Updating apt..."
        sudo apt update
    fi

    # === Step 5: Install Profile Packages ===
    log_step "Step 4: Installing ${PROFILE} profile packages..."

    PACKAGES_DIR="${PROJECT_ROOT}/packages"

    if [[ "$OS" == "macos" ]]; then
        BREWFILE="${PACKAGES_DIR}/Brewfile.${PROFILE}"
        if [[ -f "$BREWFILE" ]]; then
            log_info "Installing from ${BREWFILE}..."
            HOMEBREW_BUNDLE_NO_LOCK=1 brew bundle --file="$BREWFILE"
        else
            log_warn "Brewfile not found: ${BREWFILE}"
        fi
    else
        APT_FILE="${PACKAGES_DIR}/apt-packages.${PROFILE}"
        if [[ -f "$APT_FILE" ]]; then
            log_info "Installing from ${APT_FILE}..."
            xargs -a "$APT_FILE" sudo apt install -y
        else
            log_warn "Package list not found: ${APT_FILE}"
        fi
    fi

    # === Step 5b: Install-and-untrack casks (macOS only) ===
    if [[ "$OS" == "macos" ]]; then
        log_info "Installing self-updating apps (will untrack from Homebrew)..."
        UNTRACK_CASKS=(
            "signal"
            "whatsapp"
            "telegram"
            "google-chrome"
            "brave-browser"
            "firefox"
            "visual-studio-code"
            "1password"
            "docker"
        )
        for cask in "${UNTRACK_CASKS[@]}"; do
            if ! brew list --cask "$cask" &>/dev/null 2>&1; then
                log_info "Installing ${cask} (will untrack after)..."
                brew install --cask "$cask" && rm -rf "$(brew --prefix)/Caskroom/${cask}"
                log_info "Untracked ${cask} from Homebrew (app remains in /Applications)"
            else
                log_info "${cask} already installed, skipping"
            fi
        done
    fi

    # === Step 6: Install Modern CLI Tools ===
    log_step "Step 5: Installing modern CLI tools..."

    MODERN_TOOLS="${PROJECT_ROOT}/install/common/install-modern-tools.sh"
    if [[ -f "$MODERN_TOOLS" ]]; then
        bash "$MODERN_TOOLS"
    else
        log_warn "Modern tools installer not found"
    fi

    # === Step 5c: Ubuntu-specific extras (AWS CLI v2, Docker Engine) ===
    if [[ "$OS" == "ubuntu" ]]; then
        UBUNTU_EXTRAS="${PROJECT_ROOT}/install/ubuntu/install-ubuntu-extras.sh"
        if [[ -f "$UBUNTU_EXTRAS" ]]; then
            log_info "Installing Ubuntu-specific extras (AWS CLI v2, Docker)..."
            bash "$UBUNTU_EXTRAS"
        fi
    fi
else
    PROFILE="dotfiles-only"
    if [[ "$DRY_RUN" == true ]]; then
        echo ""
        echo -e "${BOLD}=== Dry Run Preview (dotfiles-only) ===${NC}"
        echo ""
        echo "OS: ${OS}"
        echo ""
        echo "Would symlink:"
        for f in .zshrc .zprofile .vimrc .inputrc .gitignore_global .tmux.conf .config/starship.toml .npmrc .config/atuin/config.toml; do
            echo "  ~/${f}"
        done
        echo ""
        echo "Would configure:"
        echo "  oh-my-zsh + custom plugins"
        echo "  Secrets system (1Password / pass)"
        echo "  Global git hooks (gitleaks pre-commit)"
        echo ""
        echo -e "${GREEN}No changes were made.${NC}"
        exit 0
    fi
    log_info "Dotfiles-only mode: skipping package installation"
fi

# === Global git hooks (gitleaks pre-commit) ===
HOOKS_SRC="${PROJECT_ROOT}/dotfiles/git/hooks"
HOOKS_DEST="${HOME}/.config/git/hooks"
if [[ -d "$HOOKS_SRC" ]]; then
    mkdir -p "$HOOKS_DEST"
    cp "$HOOKS_SRC"/* "$HOOKS_DEST/"
    chmod +x "$HOOKS_DEST"/*
    git config --global core.hooksPath "$HOOKS_DEST"
    log_info "Global git hooks installed at ${HOOKS_DEST}"
fi

# === Mark shared repo as git safe.directory (for two-account setup) ===
if ! git config --global --get-all safe.directory 2>/dev/null | grep -qF "$PROJECT_ROOT"; then
    log_info "Adding ${PROJECT_ROOT} to git safe.directory..."
    git config --global --add safe.directory "$PROJECT_ROOT"
fi

# === Step 7: Symlink Dotfiles ===
log_step "Step 6: Symlinking dotfiles..."

# Backup directory for this run (created on first backup)
BACKUP_DIR="${HOME}/.dotfiles-backup/$(date +%Y%m%d%H%M%S)"
BACKUP_CREATED=false

symlink_file() {
    local src="$1"
    local dest="$2"

    # Skip if symlink already points to correct target
    if [[ -L "$dest" ]] && [[ "$(readlink "$dest")" == "$src" ]]; then
        log_info "Already linked: ${dest} -> ${src}"
        return 0
    fi

    if [[ -e "$dest" ]] && [[ ! -L "$dest" ]]; then
        if [[ "$BACKUP_CREATED" == false ]]; then
            mkdir -p "$BACKUP_DIR"
            BACKUP_CREATED=true
            log_info "Backup directory: ${BACKUP_DIR}"
        fi
        local backup_name
        backup_name=$(basename "$dest")
        log_info "Backing up existing ${dest} -> ${BACKUP_DIR}/${backup_name}"
        mv "$dest" "${BACKUP_DIR}/${backup_name}"
    fi

    if [[ -L "$dest" ]]; then
        rm "$dest"
    fi

    ln -s "$src" "$dest"
    log_info "Linked: ${dest} -> ${src}"
}

# Shell configs
if [[ "$OS" == "macos" ]]; then
    symlink_file "${PROJECT_ROOT}/dotfiles/shell/.zshrc" "${HOME}/.zshrc"
    symlink_file "${PROJECT_ROOT}/dotfiles/shell/.zprofile" "${HOME}/.zprofile"
fi

# Vim
if [[ -f "${PROJECT_ROOT}/dotfiles/vim/.vimrc" ]]; then
    symlink_file "${PROJECT_ROOT}/dotfiles/vim/.vimrc" "${HOME}/.vimrc"

    # Native vim packages (replaces pathogen)
    VIM_PACK="${HOME}/.vim/pack/plugins/start"
    mkdir -p "$VIM_PACK"

    declare -A VIM_PLUGINS=(
        [fzf.vim]="https://github.com/junegunn/fzf.vim"
        [vim-ruby]="https://github.com/vim-ruby/vim-ruby"
    )

    for plugin in "${!VIM_PLUGINS[@]}"; do
        if [[ ! -d "${VIM_PACK}/${plugin}" ]]; then
            log_info "Installing vim plugin: ${plugin}..."
            git clone --quiet "${VIM_PLUGINS[$plugin]}" "${VIM_PACK}/${plugin}"
        fi
    done
fi

# Inputrc
if [[ -f "${PROJECT_ROOT}/dotfiles/misc/.inputrc" ]]; then
    symlink_file "${PROJECT_ROOT}/dotfiles/misc/.inputrc" "${HOME}/.inputrc"
fi

# Gitignore global
if [[ -f "${PROJECT_ROOT}/dotfiles/git/.gitignore_global" ]]; then
    symlink_file "${PROJECT_ROOT}/dotfiles/git/.gitignore_global" "${HOME}/.gitignore_global"
fi

# Tmux
if [[ -f "${PROJECT_ROOT}/dotfiles/tmux/.tmux.conf" ]]; then
    symlink_file "${PROJECT_ROOT}/dotfiles/tmux/.tmux.conf" "${HOME}/.tmux.conf"
fi

# Starship prompt
if [[ -f "${PROJECT_ROOT}/dotfiles/starship/starship.toml" ]]; then
    mkdir -p "${HOME}/.config"
    symlink_file "${PROJECT_ROOT}/dotfiles/starship/starship.toml" "${HOME}/.config/starship.toml"
fi

# npm security config
if [[ -f "${PROJECT_ROOT}/dotfiles/npm/.npmrc" ]]; then
    symlink_file "${PROJECT_ROOT}/dotfiles/npm/.npmrc" "${HOME}/.npmrc"
fi

# Atuin config (disable sync, update checks)
if [[ -f "${PROJECT_ROOT}/dotfiles/atuin/config.toml" ]]; then
    mkdir -p "${HOME}/.config/atuin"
    symlink_file "${PROJECT_ROOT}/dotfiles/atuin/config.toml" "${HOME}/.config/atuin/config.toml"
fi

# oh-my-zsh (install if missing)
if [[ "$OS" == "macos" ]] && [[ ! -d "${HOME}/.oh-my-zsh" ]]; then
    log_info "Installing oh-my-zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# oh-my-zsh custom plugins (per-user, cloned into ~/.oh-my-zsh/custom/plugins)
if [[ -d "${HOME}/.oh-my-zsh" ]]; then
    ZSH_CUSTOM="${HOME}/.oh-my-zsh/custom"
    log_info "Installing oh-my-zsh custom plugins..."

    declare -A OMZ_PLUGINS=(
        [zsh-autosuggestions]="https://github.com/zsh-users/zsh-autosuggestions"
        [zsh-syntax-highlighting]="https://github.com/zsh-users/zsh-syntax-highlighting"
        [zsh-completions]="https://github.com/zsh-users/zsh-completions"
        [fzf-tab]="https://github.com/Aloxaf/fzf-tab"
    )

    for plugin in "${!OMZ_PLUGINS[@]}"; do
        if [[ ! -d "${ZSH_CUSTOM}/plugins/${plugin}" ]]; then
            log_info "  Cloning ${plugin}..."
            git clone --quiet "${OMZ_PLUGINS[$plugin]}" "${ZSH_CUSTOM}/plugins/${plugin}"
        else
            log_info "  ${plugin} already installed"
        fi
    done
fi

# === Step 8: Initialize Secrets ===
log_step "Step 7: Initializing secrets system..."

SECRETS_BOOTSTRAP="${PROJECT_ROOT}/secrets/bootstrap-secrets.sh"
if [[ -f "$SECRETS_BOOTSTRAP" ]]; then
    read -p "Run secrets bootstrap now? [y/N]: " run_secrets
    if [[ "${run_secrets:-n}" == "y" ]]; then
        bash "$SECRETS_BOOTSTRAP"
    else
        log_info "Skipped. Run later: ${SECRETS_BOOTSTRAP}"
    fi
else
    log_warn "Secrets bootstrap not found"
fi

# === Step 9: Install Scheduled Updates ===
if [[ "$DOTFILES_ONLY" == false ]]; then
    log_step "Step 8: Installing scheduled update agents..."

    if [[ "$OS" == "macos" ]]; then
        # Only install for admin users
        if dseditgroup -o checkmember -m "$(whoami)" admin &>/dev/null; then
            LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
            mkdir -p "$LAUNCH_AGENTS_DIR"

            HOMEBREW_PREFIX="$(brew --prefix 2>/dev/null || echo "/opt/homebrew")"

            for template in "${PROJECT_ROOT}/scripts/launchd/"*.plist.template; do
                [[ -f "$template" ]] || continue
                local_name="$(basename "$template" .template)"
                dest="${LAUNCH_AGENTS_DIR}/${local_name}"

                # Substitute variables at install time
                sed -e "s|\${PROJECT_ROOT}|${PROJECT_ROOT}|g" \
                    -e "s|\${HOME}|${HOME}|g" \
                    -e "s|\${HOMEBREW_PREFIX}|${HOMEBREW_PREFIX}|g" \
                    "$template" > "$dest"

                # Load the agent (unload first if already loaded)
                launchctl unload "$dest" 2>/dev/null || true
                launchctl load "$dest"
                log_info "Installed launchd agent: ${local_name}"
            done
        else
            log_info "Skipping scheduled updates (non-admin user)"
        fi
    elif [[ "$OS" == "ubuntu" ]]; then
        SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
        mkdir -p "$SYSTEMD_USER_DIR"

        for unit in "${PROJECT_ROOT}/scripts/systemd/"*.{service,timer}; do
            [[ -f "$unit" ]] || continue
            cp "$unit" "$SYSTEMD_USER_DIR/"
            log_info "Installed systemd unit: $(basename "$unit")"
        done

        systemctl --user daemon-reload
        systemctl --user enable --now my-setup-update-daily.timer 2>/dev/null || true
        systemctl --user enable --now my-setup-update-interactive.timer 2>/dev/null || true
        log_info "Enabled systemd update timers"
    fi
fi

# === Step 10: Verify ===
log_step "Step 9: Verifying installation..."

verify_cmd() {
    if command -v "$1" &>/dev/null; then
        log_info "  ✓ $1"
    else
        log_warn "  ✗ $1 (not found)"
    fi
}

echo "Core tools:"
verify_cmd git
verify_cmd vim
verify_cmd tmux
verify_cmd curl

if [[ "$DOTFILES_ONLY" == false ]]; then
    echo "Modern tools:"
    verify_cmd rg
    verify_cmd fd
    verify_cmd fzf
    verify_cmd bat
    verify_cmd zoxide

    if [[ "$PROFILE" == "developer" || "$PROFILE" == "cloud-engineer" ]]; then
        echo "Development tools:"
        verify_cmd python3
        verify_cmd node
        verify_cmd go
    fi

    if [[ "$PROFILE" == "cloud-engineer" ]]; then
        echo "Cloud tools:"
        verify_cmd aws
        verify_cmd terraform
        verify_cmd docker
        verify_cmd kubectl
    fi
fi

echo "Dotfiles:"
for f in ~/.zshrc ~/.zprofile ~/.vimrc ~/.inputrc ~/.gitignore_global ~/.tmux.conf ~/.config/starship.toml ~/.npmrc; do
    if [[ -L "$f" ]]; then
        log_info "  ✓ ${f} -> $(readlink "$f")"
    elif [[ -e "$f" ]]; then
        log_warn "  ~ ${f} (exists but not a symlink)"
    fi
done

# === Done ===
echo ""
echo -e "${GREEN}${BOLD}=== Bootstrap Complete! ===${NC}"
echo ""
echo "Profile: ${PROFILE}"
echo "OS: ${OS}"
echo ""
echo "Next steps:"
echo "  1. Open a new terminal (or: source ~/.zshrc)"
echo "  2. Run: modern-tools-help  (if modern tools installed)"
echo "  3. Run: secrets_available  (check secrets system)"
echo ""
echo "To update later: update-my-system"
echo ""
