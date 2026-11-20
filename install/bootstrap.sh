#!/usr/bin/env bash
# Main Bootstrap Installer for ns-bootstrap
# Supports macOS (zsh) and Ubuntu 24.04 (zsh)
#
# Usage:
#   ./bootstrap.sh                          # Full install (admin): packages + dotfiles + secrets
#   ./bootstrap.sh --dotfiles-only          # Dotfiles only (non-admin): symlinks + oh-my-zsh + secrets
#   ./bootstrap.sh --relink                 # Re-point symlinks + machine config (after moving the repo)
#   ./bootstrap.sh --dry-run                # Preview what would be installed (no changes)
#   ./bootstrap.sh --profile minimal --yes  # Non-interactive install (for CI)
set -euo pipefail

# Detect project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Parse flags
DOTFILES_ONLY=false
RELINK=false
DRY_RUN=false
AUTO_CONFIRM=false
PROFILE=""
PROFILES="minimal developer cloud-engineer work"

usage() {
    echo "Usage: $0 [--dotfiles-only] [--relink] [--dry-run] [--profile NAME] [--yes]"
    echo ""
    echo "  --dotfiles-only   Skip package installation (for non-admin accounts)"
    echo "  --relink          Re-point dotfile symlinks and machine config, then exit"
    echo "                    (run from each account after moving the repo)"
    echo "  --dry-run         Preview what would be installed (no changes made)"
    echo "  --profile NAME    Set profile: ${PROFILES// /, }"
    echo "  --yes, -y         Skip confirmation prompts (for CI/automation)"
}

# A bad command line stops here, with status 2, before anything is touched:
# a typo such as --dryrun must never fall through to a real install.
usage_error() {
    echo "Error: $1" >&2
    echo "" >&2
    usage >&2
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dotfiles-only) DOTFILES_ONLY=true ;;
        # Relinking is a subset of dotfiles-only: it reuses that flag to skip
        # package installation, then exits once the symlinks are re-pointed.
        --relink) RELINK=true; DOTFILES_ONLY=true ;;
        --dry-run) DRY_RUN=true ;;
        --yes|-y) AUTO_CONFIRM=true ;;
        --profile)
            [[ $# -ge 2 && "$2" != -* ]] || usage_error "--profile needs a name: ${PROFILES// /, }"
            PROFILE="$2"
            shift
            ;;
        --help|-h) usage; exit 0 ;;
        *) usage_error "unknown option: $1" ;;
    esac
    shift
done
if [[ -n "$PROFILE" && " ${PROFILES} " != *" ${PROFILE} "* ]]; then
    usage_error "unknown profile: ${PROFILE} (choose ${PROFILES// /, })"
fi
# NONINTERACTIVE=1 matches Homebrew's convention
[[ "${NONINTERACTIVE:-}" == "1" ]] && AUTO_CONFIRM=true

# Source shared library
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/dotfiles.sh"
source "${SCRIPT_DIR}/lib/settings.sh"

echo ""
echo -e "${BOLD}╔═══════════════════════════════════════╗${NC}"
if [[ "$DOTFILES_ONLY" == true ]]; then
    echo -e "${BOLD}║   ns-bootstrap - Dotfiles Bootstrap       ║${NC}"
else
    echo -e "${BOLD}║     ns-bootstrap - System Bootstrap       ║${NC}"
fi
echo -e "${BOLD}╚═══════════════════════════════════════╝${NC}"
echo ""

# === Step 1: Detect OS ===
log_step "Step 1: Detecting operating system..."
detect_os
log_info "Detected: ${OS} (${PKG_MGR})"

# A Mac set up with the work profile stays on it: a plain run resolves to work,
# and naming a personal profile there is refused rather than installing
# personal apps on a company machine.
IS_WORK=false
if [[ "$(ns_remembered_profile)" == work ]]; then
    if [[ -z "$PROFILE" ]]; then
        PROFILE=work
        log_info "Profile: work (remembered in ${NS_BOOTSTRAP_PROFILE_FILE})"
    elif [[ "$PROFILE" != work ]]; then
        log_error "This Mac was set up with the work profile; --profile ${PROFILE} would install personal packages on it."
        log_error "If that is really what you want, delete ${NS_BOOTSTRAP_PROFILE_FILE} first."
        exit 2
    fi
fi
if [[ "$PROFILE" == work ]]; then
    IS_WORK=true
    if [[ "$OS" != macos ]]; then
        log_error "The work profile is for a company-managed Mac; there is no ${OS} version."
        exit 2
    fi
fi

check_settings_or_exit() {   # PROFILE
    local errors
    if ! errors="$(ns_settings_check "$1")"; then
        while IFS= read -r line; do log_error "$line"; done <<< "$errors"
        log_error "Settings come from the environment, then ${NS_BOOTSTRAP_SETTINGS_FILE}."
        exit 2
    fi
}

# On a work Mac, Homebrew must already be there and be this account's own.
# Installing it would mean running its install script from the internet, and a
# Homebrew that belongs to another account is most likely IT's to manage.
# Prints the problem, or nothing when Homebrew is fine.
work_brew_problem() {
    local prefix owner
    if ! command -v brew &>/dev/null; then
        echo "Homebrew is not installed. The work profile does not run Homebrew's install script: install it from the signed .pkg on Homebrew's GitHub releases page, or ask IT."
        return
    fi
    prefix="$(brew --prefix)"
    owner="$(stat -f "%Su" "$prefix" 2>/dev/null || echo unknown)"
    if [[ "$owner" != "$USER" ]]; then
        echo "Homebrew at ${prefix} belongs to '${owner}', so IT probably manages it. Ask IT before installing anything with it."
    elif [[ ! -w "$prefix" ]]; then
        echo "This account cannot write to Homebrew at ${prefix}. Ask IT before changing its permissions."
    fi
}

work_dry_run() {
    local brewfile="${PROJECT_ROOT}/packages/Brewfile.work" local_file problem key
    local_file="$(ns_setting_path NS_BOOTSTRAP_BREWFILE_LOCAL work)"
    echo ""
    echo -e "${BOLD}=== Dry Run Preview (work) ===${NC}"
    echo ""
    echo "OS:       ${OS} (${PKG_MGR})"
    echo "Profile:  work"
    echo ""
    if [[ "$DOTFILES_ONLY" == true ]]; then
        echo "Would install: nothing (--dotfiles-only)"
    else
        problem="$(work_brew_problem)"
        if [[ -n "$problem" ]]; then
            echo "Homebrew: a real run would stop here."
            echo "  ${problem}"
        else
            echo "Homebrew: $(brew --prefix), this account's own"
        fi
        echo ""
        echo "Would install:"
        echo "  Brewfile: ${brewfile} ($(grep -cE '^brew ' "$brewfile") packages)"
        [[ -n "$local_file" ]] && echo "  Your Brewfile: ${local_file} ($(grep -cE '^(brew|cask|mas) ' "$local_file") entries)"
        echo ""
        echo "Would skip:"
        echo "  Self-updating apps (messaging, browsers, VPNs and others)"
        echo "  The separate modern CLI tools install: Brewfile.work carries them"
        [[ -n "$(ns_setting HOMEBREW_NO_ANALYTICS work)" ]] && { echo ""; echo "Would configure:"; echo "  Homebrew analytics off"; }
    fi
    echo ""
    echo "Settings (environment, then ${NS_BOOTSTRAP_SETTINGS_FILE}, then the work default):"
    for key in NS_BOOTSTRAP_EXTRA_APPS NS_BOOTSTRAP_DAILY_UPDATE NS_BOOTSTRAP_DAILY_SCOPE NS_BOOTSTRAP_BREWFILE_LOCAL HOMEBREW_NO_ANALYTICS; do
        echo "  ${key}=$(ns_setting "$key" work) ($(ns_setting_source "$key" work))"
    done
    echo ""
    echo "Not yet handled for work: dotfiles, git hooks, secrets and scheduled updates."
    echo "A real run installs the packages above, then stops before any of those."
    echo ""
    echo -e "${GREEN}No changes were made.${NC}"
}

if [[ "$IS_WORK" == true ]]; then
    check_settings_or_exit work
    if [[ "$DRY_RUN" == true ]]; then
        work_dry_run
        exit 0
    fi
fi

if [[ "$DOTFILES_ONLY" == false ]]; then

    # === Step 2: Select Profile ===
    if [[ -z "$PROFILE" ]]; then
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
    fi

    log_info "Selected profile: ${PROFILE}"
    check_settings_or_exit "$PROFILE"

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
        for f in .zshrc .zprofile .vimrc .inputrc .gitignore_global .tmux.conf .config/starship.toml .npmrc .config/atuin/config.toml .config/pip/pip.conf; do
            echo "  ~/${f}"
        done
        echo ""
        echo "Would configure:"
        echo "  oh-my-zsh + custom plugins"
        echo "  Secrets system (1Password / pass)"
        echo "  Scheduled update agents (launchd / systemd)"
        echo "  Global git hooks (gitleaks pre-commit + pre-push, AI-trailer stripping)"
        echo ""
        echo -e "${GREEN}No changes were made.${NC}"
        exit 0
    fi

    # === Step 3: Check permissions and confirm ===
    if [[ "$IS_WORK" == true ]]; then
        brew_problem="$(work_brew_problem)"
        if [[ -n "$brew_problem" ]]; then
            log_error "$brew_problem"
            log_error "Nothing was changed."
            exit 1
        fi
    elif [[ "$OS" == "macos" ]]; then
        check_brew_permissions
    fi

    echo ""
    echo -e "${YELLOW}This will:${NC}"
    if [[ "$IS_WORK" == true ]]; then
        echo "  - Install the work packages (packages/Brewfile.work) via brew"
        echo "  - Stop before dotfiles, git hooks and secrets (not yet handled for work)"
    else
        echo "  - Install ${PROFILE} packages via ${PKG_MGR}"
        echo "  - Install modern CLI tools (ripgrep, fd, fzf, bat, zoxide, etc.)"
        echo "  - Symlink dotfiles (with backup of existing)"
        echo "  - Initialize secrets system"
    fi
    echo ""
    if [[ "$AUTO_CONFIRM" == true ]]; then
        log_info "Auto-confirmed (--yes)"
    else
        read -p "Continue? [y/N]: " confirm
        [[ "${confirm:-n}" != "y" ]] && { echo "Aborted."; exit 0; }
    fi

    if [[ "$IS_WORK" == true ]]; then
        mkdir -p "$(dirname "$NS_BOOTSTRAP_PROFILE_FILE")"
        echo work > "$NS_BOOTSTRAP_PROFILE_FILE"
        log_info "Remembered the work profile in ${NS_BOOTSTRAP_PROFILE_FILE}"
    fi

    # === Step 4: Install Package Manager ===
    log_step "Step 3: Ensuring package manager is available..."

    if [[ "$OS" == "macos" ]]; then
        if ! command -v brew &>/dev/null; then
            log_info "Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

            # Add to PATH for current session
            eval "$(/opt/homebrew/bin/brew shellenv)"
        else
            log_info "Homebrew already installed"
        fi
        if [[ -n "$(ns_setting HOMEBREW_NO_ANALYTICS "$PROFILE")" ]]; then
            export HOMEBREW_NO_ANALYTICS=1
            brew analytics off
            log_info "Homebrew analytics off"
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
            # Trust declared third-party taps BEFORE bundling. Homebrew's tap-trust
            # enforcement blocks installing/updating from an untrusted tap, and bundle
            # taps + installs in one step — so tap then trust each first. (brew trust is a
            # recent feature; skip quietly on older versions.)
            if brew help trust >/dev/null 2>&1; then
                while IFS= read -r tap_name; do
                    [[ -n "$tap_name" ]] || continue
                    brew tap "$tap_name" >/dev/null 2>&1 || true
                    if brew trust "$tap_name" >/dev/null 2>&1; then
                        log_info "Trusted tap: ${tap_name}"
                    else
                        log_warn "Could not trust tap: ${tap_name}"
                    fi
                done < <(grep -E '^[[:space:]]*tap[[:space:]]' "$BREWFILE" \
                         | sed -E 's/^[[:space:]]*tap[[:space:]]+"([^"]+)".*/\1/')
            fi

            # Migrate a core ffmpeg to the homebrew-ffmpeg tap build before bundling, so
            # the tap formula installs without a binary-symlink conflict. Idempotent: skip
            # if it is already the tap build. Receipt grep (not jq, which may not be
            # installed yet) reads the keg's recorded source tap.
            if grep -q '"homebrew-ffmpeg/ffmpeg/ffmpeg"' "$BREWFILE" \
               && brew list --formula ffmpeg >/dev/null 2>&1; then
                ffmpeg_cellar="$(brew --cellar ffmpeg 2>/dev/null)"
                if grep -qs 'homebrew-ffmpeg/ffmpeg' "$ffmpeg_cellar"/*/INSTALL_RECEIPT.json; then
                    log_info "ffmpeg already from homebrew-ffmpeg/ffmpeg; leaving as is."
                else
                    log_info "Replacing core ffmpeg with the homebrew-ffmpeg/ffmpeg build..."
                    brew uninstall --ignore-dependencies ffmpeg || true
                fi
            fi

            total=$(grep -cE '^(brew|cask|mas) ' "$BREWFILE")
            log_info "Installing ${total} packages from ${BREWFILE}..."
            if ! HOMEBREW_BUNDLE_NO_LOCK=1 brew bundle --file="$BREWFILE" --verbose; then
                log_warn "Some packages failed to install."
                log_warn "Re-run: brew bundle --file=${BREWFILE} --verbose"
            fi
        else
            log_warn "Brewfile not found: ${BREWFILE}"
        fi

        # A Brewfile of your own (apps the company prefers, say), kept outside
        # this repository and named by NS_BOOTSTRAP_BREWFILE_LOCAL.
        LOCAL_BREWFILE="$(ns_setting_path NS_BOOTSTRAP_BREWFILE_LOCAL "$PROFILE")"
        if [[ -n "$LOCAL_BREWFILE" ]]; then
            log_info "Installing from your Brewfile: ${LOCAL_BREWFILE}"
            if ! HOMEBREW_BUNDLE_NO_LOCK=1 brew bundle --file="$LOCAL_BREWFILE" --verbose; then
                log_warn "Some packages from your Brewfile failed to install."
            fi
        fi
    else
        APT_FILE="${PACKAGES_DIR}/apt-packages.${PROFILE}"
        if [[ -f "$APT_FILE" ]]; then
            log_info "Installing from ${APT_FILE}..."
            grep -v '^\s*#' "$APT_FILE" | grep -v '^\s*$' | xargs sudo apt install -y
        else
            log_warn "Package list not found: ${APT_FILE}"
        fi
    fi

    # === Step 5b: Install-and-untrack casks (macOS only) ===
    # Off for work, where these apps are personal or need a business licence.
    if [[ "$OS" == "macos" && "$(ns_setting NS_BOOTSTRAP_EXTRA_APPS "$PROFILE")" == off ]]; then
        log_info "Skipping self-updating apps (NS_BOOTSTRAP_EXTRA_APPS=off)"
    elif [[ "$OS" == "macos" ]]; then
        log_info "Installing self-updating apps (will untrack from Homebrew)..."
        UNTRACK_CASKS=(
            # Messaging (standalone installs, not in Brewfile)
            "signal"
            "whatsapp"
            "telegram"
            # Browsers (all have built-in auto-updaters)
            "google-chrome"
            "brave-browser"
            "firefox"
            "microsoft-edge"
            "tor-browser"
            # Apps with built-in auto-updaters
            "visual-studio-code"
            "1password"
            "docker-desktop"
            "google-drive"
            "slack"
            "zoom"
            "microsoft-teams"
            "microsoft-auto-update"
            "mullvad-vpn"
            "orbstack"
            "ghostty"
            "iterm2"
            "keka"
            "proxyman"
            "rectangle"
            "tunnelblick"
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
        NS_BOOTSTRAP_PROFILE="$PROFILE" bash "$MODERN_TOOLS"
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
        if [[ "$RELINK" == true ]]; then
            echo -e "${BOLD}=== Dry Run Preview (relink) ===${NC}"
        else
            echo -e "${BOLD}=== Dry Run Preview (dotfiles-only) ===${NC}"
        fi
        echo ""
        echo "OS: ${OS}"
        echo ""
        echo "Would symlink:"
        for f in .zshrc .zprofile .vimrc .inputrc .gitignore_global .tmux.conf .config/starship.toml .npmrc .config/atuin/config.toml .config/pip/pip.conf; do
            echo "  ~/${f}"
        done
        echo ""
        echo "Would configure:"
        echo "  NS_BOOTSTRAP_DIR=${PROJECT_ROOT} in ~/.config/ns-bootstrap/config"
        echo "  Global git hooks (gitleaks pre-commit + pre-push, AI-trailer stripping)"
        if [[ "$RELINK" == false ]]; then
            echo "  oh-my-zsh + custom plugins"
            echo "  Secrets system (1Password / pass)"
        fi
        echo ""
        echo -e "${GREEN}No changes were made.${NC}"
        exit 0
    fi
    log_info "Dotfiles-only mode: skipping package installation"
fi

# The work profile stops here until its dotfile, git-hook and secrets handling
# exist: the steps below would replace files and settings that a company Mac's
# IT may own.
if [[ "$IS_WORK" == true ]]; then
    echo ""
    if [[ "$DOTFILES_ONLY" == true ]]; then
        log_warn "Nothing to do yet for --dotfiles-only --profile work: dotfiles, git hooks and secrets are not handled for work yet."
        exit 1
    fi
    log_info "Work packages installed."
    log_warn "Stopping before dotfiles, git hooks and secrets: they are not handled for the work profile yet. Nothing else was changed."
    exit 0
fi

# === Global git hooks (secrets scan + AI trailer stripping) ===
HOOKS_SRC="${PROJECT_ROOT}/dotfiles/git/hooks"
HOOKS_DEST="${HOME}/.config/git/hooks"
if [[ -d "$HOOKS_SRC" ]]; then
    mkdir -p "$HOOKS_DEST"
    # -R so the lib/ subdir (shared helpers) is copied, not just top-level files.
    cp -R "$HOOKS_SRC"/. "$HOOKS_DEST/"
    # Only the hook entrypoints need +x; sourced helpers under lib/ do not.
    chmod +x "$HOOKS_DEST"/pre-commit "$HOOKS_DEST"/pre-push \
             "$HOOKS_DEST"/commit-msg "$HOOKS_DEST"/prepare-commit-msg
    git config --global core.hooksPath "$HOOKS_DEST"
    log_info "Global git hooks installed at ${HOOKS_DEST}"
fi

# === Mark shared repo as git safe.directory (for two-account setup) ===
if ! git config --global --get-all safe.directory 2>/dev/null | grep -qF "$PROJECT_ROOT"; then
    log_info "Adding ${PROJECT_ROOT} to git safe.directory..."
    git config --global --add safe.directory "$PROJECT_ROOT"
fi

# === Write NS_BOOTSTRAP_DIR to machine config ===
# Ensures shell loader can find the repo regardless of clone location.
# bootstrap-secrets.sh will overwrite this file with full config on first run,
# but preserves NS_BOOTSTRAP_DIR.
NS_BOOTSTRAP_CONFIG_DIR="${HOME}/.config/ns-bootstrap"
NS_BOOTSTRAP_CONFIG_FILE="${NS_BOOTSTRAP_CONFIG_DIR}/config"
mkdir -p "$NS_BOOTSTRAP_CONFIG_DIR"
if [[ ! -f "$NS_BOOTSTRAP_CONFIG_FILE" ]]; then
    cat > "$NS_BOOTSTRAP_CONFIG_FILE" << EOF
# ns-bootstrap — Machine-specific settings (non-secret)
# Generated by bootstrap.sh on $(date +%Y-%m-%d)
# Run secrets/bootstrap-secrets.sh to complete configuration

NS_BOOTSTRAP_DIR="${PROJECT_ROOT}"
EOF
    log_info "Written: ${NS_BOOTSTRAP_CONFIG_FILE}"
elif grep -q '^NS_BOOTSTRAP_DIR=' "$NS_BOOTSTRAP_CONFIG_FILE"; then
    # A stale value here is silent: .zshrc sources the loader behind an [[ -f ]]
    # guard, so a moved repo just makes every shell function disappear.
    current_dir="$(sed -n 's/^NS_BOOTSTRAP_DIR="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$NS_BOOTSTRAP_CONFIG_FILE")"
    if [[ "$current_dir" != "$PROJECT_ROOT" ]]; then
        sed -i.bak "s|^NS_BOOTSTRAP_DIR=.*|NS_BOOTSTRAP_DIR=\"${PROJECT_ROOT}\"|" "$NS_BOOTSTRAP_CONFIG_FILE"
        rm -f "${NS_BOOTSTRAP_CONFIG_FILE}.bak"
        log_info "Updated NS_BOOTSTRAP_DIR: ${current_dir} -> ${PROJECT_ROOT}"
    fi
else
    sed -i.bak "2a\\
NS_BOOTSTRAP_DIR=\"${PROJECT_ROOT}\"
" "$NS_BOOTSTRAP_CONFIG_FILE"
    rm -f "${NS_BOOTSTRAP_CONFIG_FILE}.bak"
    log_info "Added NS_BOOTSTRAP_DIR to ${NS_BOOTSTRAP_CONFIG_FILE}"
fi

# === Step 7: Symlink Dotfiles ===
log_step "Step 6: Symlinking dotfiles..."

# Backup directory for this run (created on first backup). symlink_file
# (install/lib/dotfiles.sh) reads these and updates BACKUP_CREATED.
# shellcheck disable=SC2034
BACKUP_DIR="${HOME}/.dotfiles-backup/$(date +%Y%m%d%H%M%S)"
# shellcheck disable=SC2034
BACKUP_CREATED=false
LINKS_CHANGED=0

# Shell configs
if [[ "$OS" == "macos" ]]; then
    symlink_file "${PROJECT_ROOT}/dotfiles/shell/.zshrc" "${HOME}/.zshrc"
    symlink_file "${PROJECT_ROOT}/dotfiles/shell/.zprofile" "${HOME}/.zprofile"
else
    symlink_file "${PROJECT_ROOT}/dotfiles/shell/.zshrc.ubuntu" "${HOME}/.zshrc"
    symlink_file "${PROJECT_ROOT}/dotfiles/shell/.zprofile.ubuntu" "${HOME}/.zprofile"
fi

# Vim
if [[ -f "${PROJECT_ROOT}/dotfiles/vim/.vimrc" ]]; then
    symlink_file "${PROJECT_ROOT}/dotfiles/vim/.vimrc" "${HOME}/.vimrc"
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

# npm security config. A ~/.npmrc of your own (a company registry, a CA file,
# an auth token) is kept, as pip.conf is below: replacing it would quietly
# change where npm installs from.
if [[ -f "${PROJECT_ROOT}/dotfiles/npm/.npmrc" ]]; then
    if [[ -e "${HOME}/.npmrc" && ! -L "${HOME}/.npmrc" ]]; then
        log_warn "Keeping your ~/.npmrc; for ns-bootstrap's hardening, add the lines from ${PROJECT_ROOT}/dotfiles/npm/.npmrc (ignore-scripts=true first)"
    else
        symlink_file "${PROJECT_ROOT}/dotfiles/npm/.npmrc" "${HOME}/.npmrc"
    fi
fi

# Atuin config (disable sync, update checks)
if [[ -f "${PROJECT_ROOT}/dotfiles/atuin/config.toml" ]]; then
    mkdir -p "${HOME}/.config/atuin"
    symlink_file "${PROJECT_ROOT}/dotfiles/atuin/config.toml" "${HOME}/.config/atuin/config.toml"
fi

# pip: refuse installs outside a virtualenv for every process that runs pip,
# not only login shells. A pip.conf of the user's own (an index, a proxy) is
# kept: replacing it would quietly change where pip installs from.
if [[ -f "${PROJECT_ROOT}/dotfiles/pip/pip.conf" ]]; then
    if [[ "$OS" == "macos" ]]; then
        PIP_CONF_DIR="${HOME}/.config/pip"
    else
        PIP_CONF_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/pip"
    fi
    if [[ -e "${PIP_CONF_DIR}/pip.conf" && ! -L "${PIP_CONF_DIR}/pip.conf" ]]; then
        log_warn "Keeping your ${PIP_CONF_DIR}/pip.conf; add 'require-virtualenv = true' under [global] to refuse installs outside a virtualenv"
    else
        mkdir -p "$PIP_CONF_DIR"
        symlink_file "${PROJECT_ROOT}/dotfiles/pip/pip.conf" "${PIP_CONF_DIR}/pip.conf"
    fi
    if [[ "$OS" == "macos" && -d "${HOME}/Library/Application Support/pip" ]]; then
        log_warn "pip reads ~/Library/Application Support/pip/pip.conf on this Mac, so ${PIP_CONF_DIR}/pip.conf has no effect"
    fi
fi

# Relinking stops here: everything above re-derives from PROJECT_ROOT (symlinks,
# machine config, git hooks, safe.directory), which is all a repo move invalidates.
if [[ "$RELINK" == true ]]; then
    echo ""
    if [[ "$LINKS_CHANGED" -eq 0 ]]; then
        log_info "Relink complete — all links already pointed at ${PROJECT_ROOT}"
    else
        log_info "Relink complete — ${LINKS_CHANGED} link(s) re-pointed at ${PROJECT_ROOT}"
        log_warn "Open a new login shell for the change to take effect."
    fi
    exit 0
fi

# oh-my-zsh, its custom plugins and the vim plugins, each checked out at the
# commit pinned in packages/git-pins rather than whatever upstream holds today.
# This replaces oh-my-zsh's own installer, which ran from master via curl | sh
# and, with --unattended --keep-zshrc, amounted to little more than a clone.
log_info "Installing oh-my-zsh and plugins at their pinned commits..."
bash "${PROJECT_ROOT}/install/common/sync-git-pins.sh"

# Set zsh as default shell on Ubuntu (takes effect on next login)
if [[ "$OS" == "ubuntu" ]] && [[ "$SHELL" != */zsh ]]; then
    log_info "Setting zsh as default shell (takes effect on next login)..."
    sudo usermod -s /usr/bin/zsh "$USER"
fi

# === Step 8: Initialize Secrets ===
log_step "Step 7: Initializing secrets system..."

SECRETS_BOOTSTRAP="${PROJECT_ROOT}/secrets/bootstrap-secrets.sh"
if [[ -f "$SECRETS_BOOTSTRAP" ]]; then
    if [[ "$AUTO_CONFIRM" == true ]]; then
        log_info "Skipping secrets in non-interactive mode. Run later: ${SECRETS_BOOTSTRAP}"
    else
        read -p "Run secrets bootstrap now? [y/N]: " run_secrets
        if [[ "${run_secrets:-n}" == "y" ]]; then
            bash "$SECRETS_BOOTSTRAP"
        else
            log_info "Skipped. Run later: ${SECRETS_BOOTSTRAP}"
        fi
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
            mkdir -p "${HOME}/.local/log"

            HOMEBREW_PREFIX="$(brew --prefix 2>/dev/null || echo "/opt/homebrew")"
            LAUNCHD_USER="gui/$(id -u)"

            # Clean up stale update agents before reinstalling the current ones:
            #   * interactive agents — that tier is now on-demand (run update-my-system),
            #     so any previously-scheduled one is removed.
            #   * daily agents whose backing script no longer exists — orphans left by an
            #     earlier install or a project rename (their label changed; the plist lingers).
            for plist in "${LAUNCH_AGENTS_DIR}"/com.*.update-daily.plist \
                         "${LAUNCH_AGENTS_DIR}"/com.*.update-interactive.plist; do
                [[ -f "$plist" ]] || continue
                stale_label="$(basename "$plist" .plist)"
                stale_script="$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:1' "$plist" 2>/dev/null)"
                if [[ "$stale_label" == *update-interactive ]] || [[ -n "$stale_script" && ! -f "$stale_script" ]]; then
                    launchctl bootout "${LAUNCHD_USER}/${stale_label}" 2>/dev/null || true
                    rm -f "$plist"
                    log_info "Removed stale update agent: ${stale_label}"
                fi
            done

            if [[ "$(ns_setting NS_BOOTSTRAP_DAILY_UPDATE "$PROFILE")" == off ]]; then
                # Switched off: remove the agent an earlier run installed.
                for template in "${PROJECT_ROOT}/scripts/launchd/"*.plist.template; do
                    [[ -f "$template" ]] || continue
                    label="$(basename "$template" .plist.template)"
                    if [[ -f "${LAUNCH_AGENTS_DIR}/${label}.plist" ]]; then
                        launchctl bootout "${LAUNCHD_USER}/${label}" 2>/dev/null || true
                        rm -f "${LAUNCH_AGENTS_DIR}/${label}.plist"
                        log_info "Removed launchd agent: ${label}.plist"
                    fi
                done
                log_info "Daily update agent off (NS_BOOTSTRAP_DAILY_UPDATE=off)"
            else
                for template in "${PROJECT_ROOT}/scripts/launchd/"*.plist.template; do
                    [[ -f "$template" ]] || continue
                    local_name="$(basename "$template" .template)"
                    label="${local_name%.plist}"
                    dest="${LAUNCH_AGENTS_DIR}/${local_name}"

                    # Substitute variables at install time
                    sed -e "s|\${PROJECT_ROOT}|${PROJECT_ROOT}|g" \
                        -e "s|\${HOME}|${HOME}|g" \
                        -e "s|\${HOMEBREW_PREFIX}|${HOMEBREW_PREFIX}|g" \
                        "$template" > "$dest"

                    # Use modern launchctl bootstrap (load/unload deprecated since macOS 10.10).
                    # Requires an active GUI session — silently deferred if run via su/SSH.
                    # macOS auto-loads LaunchAgents from ~/Library/LaunchAgents on next GUI login.
                    launchctl bootout "${LAUNCHD_USER}/${label}" 2>/dev/null || true
                    if launchctl bootstrap "${LAUNCHD_USER}" "$dest" 2>/dev/null; then
                        log_info "Installed and loaded launchd agent: ${local_name}"
                    else
                        log_info "Installed launchd agent: ${local_name} (will load on next GUI login)"
                    fi
                done

                # A per-user LaunchAgent only runs while its owner is logged in at the GUI.
                # If the brew owner (this admin account) is not the console login user,
                # the agent will never fire — point them at the opt-in LaunchDaemon.
                console_user="$(stat -f '%Su' /dev/console 2>/dev/null)"
                if [[ -n "$console_user" && "$console_user" != "$(whoami)" ]]; then
                    log_warn "Update agent installed for '$(whoami)', but the GUI login user is '${console_user}'."
                    log_warn "Per-user agents only run while their owner is logged in, so this may never fire."
                    log_warn "For a multi-account setup, install the LaunchDaemon instead:"
                    log_warn "  scripts/launchd-daemon/com.ns-bootstrap.update-daily.daemon.plist.template"
                fi
            fi
        else
            log_info "Skipping scheduled updates (non-admin user)"
        fi
    elif [[ "$OS" == "ubuntu" ]]; then
        # Daily security updates come from Ubuntu's unattended-upgrades, which
        # the package lists install and apt's own timer runs as root. A
        # per-user timer cannot run apt: sudo has no terminal to ask for a
        # password on. Full updates stay on demand: run update-my-system.
        # Machines bootstrapped earlier carry such a timer; remove it.
        SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
        if [[ -e "${SYSTEMD_USER_DIR}/ns-bootstrap-update-daily.timer" ]]; then
            systemctl --user disable --now ns-bootstrap-update-daily.timer 2>/dev/null || true
            rm -f "${SYSTEMD_USER_DIR}"/ns-bootstrap-update-daily.{service,timer} \
                  "${SYSTEMD_USER_DIR}/timers.target.wants/ns-bootstrap-update-daily.timer"
            systemctl --user daemon-reload 2>/dev/null || true
            log_info "Removed the old per-user daily update timer (it could not run apt)"
        fi
        log_info "Daily security updates: unattended-upgrades; run update-my-system for the rest"
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
        verify_cmd gh
        verify_cmd go
        verify_cmd shellcheck
        verify_cmd mise
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
if [[ "$OS" == "macos" ]]; then
    echo "  1. Open a new terminal (or: source ~/.zshrc)"
    echo "  2. Run: modern-tools-help  (if modern tools installed)"
    echo "  3. Run: secrets_available  (check secrets system)"
    echo ""
    echo "To update later: update-my-system"
else
    echo "  1. Log out and back in — zsh is now your default shell"
    echo "  2. Verify tools: command -v rg fd fzf bat zoxide eza delta"
    echo "  3. Check secrets: pass show ns-bootstrap/git-personal/name"
fi
echo ""
