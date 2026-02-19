#!/usr/bin/env bash
# Install Modern CLI Tools
# Replaces traditional Unix tools with modern, faster alternatives
set -euo pipefail

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

echo "=== Installing Modern CLI Tools ==="
echo ""

# Detect OS
detect_os
log_info "Detected OS: $OS"
echo ""

if [[ "$OS" == "macos" ]]; then
    log_info "Installing via Homebrew..."

    # Check if brew is available
    if ! command -v brew &> /dev/null; then
        log_error "Homebrew not found. Please install: https://brew.sh"
        exit 1
    fi

    # Verify current user has permission to use brew
    check_brew_permissions

    # Modern CLI tools
    log_info "Installing core modern tools..."
    brew install \
        ripgrep \
        fd \
        fzf \
        bat \
        zoxide \
        eza \
        git-delta

    log_info "Installing system monitoring tools..."
    brew install \
        btop \
        dust \
        duf \
        procs \
        hyperfine

    log_info "Installing additional utilities..."
    brew install \
        httpie \
        doggo \
        gping \
        tldr \
        direnv \
        jq \
        yq

    # Post-install: fzf key bindings
    log_info "Setting up fzf key bindings..."
    if [[ -f "$(brew --prefix)/opt/fzf/install" ]]; then
        "$(brew --prefix)/opt/fzf/install" --key-bindings --completion --no-update-rc
    fi

    # Post-install: bat cache
    log_info "Building bat cache..."
    bat cache --build &> /dev/null || true

    # Atuin (modern shell history)
    log_info "Installing atuin (shell history)..."
    brew install atuin

    log_info "macOS modern tools installed successfully!"

else
    log_info "Installing via apt and cargo..."

    # Update package list
    sudo apt update

    # Tools available via apt
    log_info "Installing apt packages..."
    sudo apt install -y \
        ripgrep \
        fd-find \
        fzf \
        bat \
        httpie \
        direnv \
        jq

    # Create symlinks for fd and bat (Ubuntu uses different names)
    if ! command -v fd &> /dev/null && command -v fdfind &> /dev/null; then
        log_info "Creating fd symlink..."
        sudo ln -sf "$(which fdfind)" /usr/local/bin/fd
    fi

    if ! command -v bat &> /dev/null && command -v batcat &> /dev/null; then
        log_info "Creating bat symlink..."
        sudo ln -sf "$(which batcat)" /usr/local/bin/bat
    fi

    # Install cargo if not present
    if ! command -v cargo &> /dev/null; then
        log_info "Installing Rust toolchain..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    fi

    # Ensure C toolchain is present — cargo needs cc/ld and libc6-dev (Scrt1.o, crti.o)
    log_info "Ensuring C build toolchain is present..."
    sudo apt install -y gcc libc6-dev

    # Tools that need cargo
    log_info "Installing cargo packages (this may take a while)..."
    cargo install \
        zoxide \
        eza \
        git-delta \
        bottom \
        du-dust \
        procs \
        hyperfine \
        bandwhich

    # duf (better df) — available via apt on Ubuntu 22.04+
    if ! command -v duf &> /dev/null; then
        log_info "Installing duf..."
        sudo apt install -y duf
    fi

    # doggo (DNS tool) - install via snap
    log_info "Installing doggo (DNS lookup tool)..."
    if ! command -v doggo &> /dev/null; then
        if command -v snap &> /dev/null; then
            sudo snap install doggo
        else
            log_warn "snap not available, skipping doggo install"
        fi
    else
        log_info "doggo already installed"
    fi

    # kdig (advanced DNS tool from Knot DNS)
    log_info "Installing kdig (DNS lookup tool)..."
    sudo apt install -y knot-dnsutils

    # Atuin (modern shell history)
    log_info "Installing atuin (shell history)..."
    if ! command -v atuin &>/dev/null; then
        curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh
    else
        log_info "atuin already installed"
    fi

    log_info "Ubuntu modern tools installed successfully!"
fi

# === Install oh-my-zsh custom plugins ===
ZSH_CUSTOM="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"
if [[ -d "${HOME}/.oh-my-zsh" ]]; then
    log_info "Installing oh-my-zsh custom plugins..."

    if [[ ! -d "${ZSH_CUSTOM}/plugins/fzf-tab" ]]; then
        git clone https://github.com/Aloxaf/fzf-tab "${ZSH_CUSTOM}/plugins/fzf-tab"
    fi

    if [[ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]]; then
        git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
    fi

    if [[ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ]]; then
        git clone https://github.com/zsh-users/zsh-syntax-highlighting "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"
    fi

    if [[ ! -d "${ZSH_CUSTOM}/plugins/zsh-completions" ]]; then
        git clone https://github.com/zsh-users/zsh-completions "${ZSH_CUSTOM}/plugins/zsh-completions"
    fi

    log_info "oh-my-zsh custom plugins installed"
fi

echo ""
log_info "=== Installation Complete ==="
echo ""
echo "Modern CLI tools installed:"
echo "  • ripgrep (rg)   - Better grep"
echo "  • fd             - Better find"
echo "  • fzf            - Fuzzy finder"
echo "  • bat            - Better cat with syntax highlighting"
echo "  • zoxide (z)     - Smart cd replacement"
echo "  • eza            - Better ls"
echo "  • delta          - Better git diff"
echo "  • btop/bottom    - Better top"
echo "  • dust           - Better du"
echo "  • duf            - Better df"
echo "  • procs          - Better ps"
echo "  • doggo          - Better dig (DNS lookup, DoH/DoT/DoQ)"
echo "  • httpie         - Better curl"
echo "  • direnv         - Directory-based env vars"
echo ""
echo "Next steps:"
echo "  1. Source your shell config to load new tools"
echo "  2. Add aliases from shell/aliases/modern-tools.sh"
echo "  3. Configure zoxide: eval \"\$(zoxide init zsh)\""
echo "  4. Configure direnv: eval \"\$(direnv hook zsh)\""
echo ""
