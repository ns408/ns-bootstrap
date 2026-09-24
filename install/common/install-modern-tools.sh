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
    log_info "Installing via apt and prebuilt binaries..."

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
        jq \
        gnupg

    # Create symlinks for fd and bat (Ubuntu uses different names)
    if ! command -v fd &> /dev/null && command -v fdfind &> /dev/null; then
        log_info "Creating fd symlink..."
        sudo ln -sf "$(which fdfind)" /usr/local/bin/fd
    fi

    if ! command -v bat &> /dev/null && command -v batcat &> /dev/null; then
        log_info "Creating bat symlink..."
        sudo ln -sf "$(which batcat)" /usr/local/bin/bat
    fi

    # cargo-binstall fetches each tool's prebuilt release binary instead of
    # compiling it. Building them from source cost about eight minutes, pulled
    # in a whole Rust toolchain to install seven small utilities, and left the
    # bootstrap hostage to any crate that stops compiling on current rustc —
    # which is exactly how this path broke.
    #
    # binstall itself is pinned by version and checksum, so an upgrade is a
    # deliberate commit rather than whatever "latest" resolves to on the day.
    # (cargo-bins does publish sigstore attestations, but verifying those needs
    # the gh CLI, which Ubuntu installs later than this script runs.)
    BINSTALL_VERSION="1.23.0"
    ARCH=$(dpkg --print-architecture)
    if [[ "$ARCH" == "arm64" ]]; then
        BINSTALL_TARGET="aarch64-unknown-linux-musl"
        BINSTALL_SHA256="ba9b7bf426c7b7375825cd3fa367c3f8a632ca7c6c546fdcb738114b167f4103"
    else
        BINSTALL_TARGET="x86_64-unknown-linux-musl"
        BINSTALL_SHA256="64bf954c68bb558431deeabecaec7687edd5541c2189ee263bb8bc18bc4fdf55"
    fi

    if ! command -v cargo-binstall &> /dev/null; then
        log_info "Installing cargo-binstall ${BINSTALL_VERSION}..."
        BINSTALL_TGZ="/tmp/cargo-binstall-${BINSTALL_TARGET}.tgz"
        curl --proto '=https' --tlsv1.2 -fsSL \
            "https://github.com/cargo-bins/cargo-binstall/releases/download/v${BINSTALL_VERSION}/cargo-binstall-${BINSTALL_TARGET}.tgz" \
            -o "$BINSTALL_TGZ"
        if ! echo "${BINSTALL_SHA256}  ${BINSTALL_TGZ}" | sha256sum -c -; then
            rm -f "$BINSTALL_TGZ"
            log_error "cargo-binstall checksum verification failed — refusing to install"
            exit 1
        fi
        tar -xzf "$BINSTALL_TGZ" -C /tmp/ cargo-binstall
        sudo install -m 755 /tmp/cargo-binstall /usr/local/bin/cargo-binstall
        rm -f "$BINSTALL_TGZ" /tmp/cargo-binstall
    fi

    # eza (better ls) — from the maintainer's signed apt repo, not cargo. eza pins
    # palette at =0.7.5, which no longer compiles on current stable rustc, and the
    # source build cost ~10 minutes. apt verifies the package signature, which is
    # stronger than the unsigned release tarballs (eza publishes no checksums).
    # The repo is pinned to the eza package alone, so trusting its key cannot
    # shadow anything else in apt.
    if ! command -v eza &> /dev/null; then
        log_info "Installing eza from the official apt repository..."
        sudo mkdir -p -m 755 /etc/apt/keyrings
        curl --proto '=https' --tlsv1.2 -fsSL \
            https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
            | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
        echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
            | sudo tee /etc/apt/sources.list.d/gierens.list > /dev/null
        sudo tee /etc/apt/preferences.d/gierens > /dev/null << 'PIN'
Package: *
Pin: origin deb.gierens.de
Pin-Priority: 1

Package: eza
Pin: origin deb.gierens.de
Pin-Priority: 500
PIN
        sudo chmod 644 /etc/apt/keyrings/gierens.gpg \
            /etc/apt/sources.list.d/gierens.list /etc/apt/preferences.d/gierens
        sudo apt update
        sudo apt install -y eza
    fi

    # Rust CLI tools (atuin included), one at a time: these are conveniences, and
    # one crate whose release assets change shape upstream must not abort the
    # whole bootstrap. The list lives in packages/ so update-my-system upgrades
    # exactly what was installed. --disable-strategies compile refuses the
    # source-build fallback outright, since that slow path is what this replaces.
    # --root rather than --install-path: it records what was installed, so a
    # re-run skips tools that are already current instead of downloading them.
    log_info "Installing Rust CLI tools (prebuilt binaries)..."
    mkdir -p "${HOME}/.local/bin"
    tools_failed=()
    while IFS= read -r crate; do
        [[ -z "$crate" || "$crate" == \#* ]] && continue
        if ! cargo-binstall --no-confirm --disable-strategies compile \
            --root "${HOME}/.local" "$crate"; then
            log_warn "cargo-binstall ${crate} failed — continuing"
            tools_failed+=("$crate")
        fi
    done < "${SCRIPT_DIR}/../../packages/binstall-tools.ubuntu"
    if [[ ${#tools_failed[@]} -gt 0 ]]; then
        log_warn "Tools that failed to install: ${tools_failed[*]}"
    fi

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

    # mise (version manager): the release tarball, checked against mise's
    # GPG-signed checksums, rather than the mise.run script. That script does
    # verify a checksum, but one embedded in itself, so both come from the same
    # server. SHASUMS256.asc is clearsigned: the checksums are read from the
    # text gpg verified, never from the separately published SHASUMS256.txt,
    # which could be swapped while a valid signature stayed in place.
    # Installs to ~/.local/bin/mise, where mise.run put it, so `mise
    # self-update` in update-my-system carries on working unchanged.
    install_mise_verified() {
        local key_fpr="24853EC9F655CE80B48E6C3A8B81C9D17413A06D"
        local version arch asset work fpr status
        version=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
            https://github.com/jdx/mise/releases/latest | sed 's#.*/tag/v##')
        [[ "$(dpkg --print-architecture)" == "arm64" ]] && arch="linux-arm64" || arch="linux-x64"
        asset="mise-v${version}-${arch}.tar.gz"
        work=$(mktemp -d)

        if [[ -z "$version" ]] \
            || ! curl --proto '=https' --tlsv1.2 -fsSL -o "${work}/${asset}" \
                "https://github.com/jdx/mise/releases/download/v${version}/${asset}" \
            || ! curl --proto '=https' --tlsv1.2 -fsSL -o "${work}/SHASUMS256.asc" \
                "https://github.com/jdx/mise/releases/download/v${version}/SHASUMS256.asc" \
            || ! curl --proto '=https' --tlsv1.2 -fsSL -o "${work}/mise.pub" \
                https://mise.jdx.dev/gpg-key.pub; then
            log_warn "Could not download mise ${version:-(unresolved version)} — skipping"
            rm -rf "$work"
            return 0
        fi

        # A download failure above is only an outage; from here on a failure
        # means something does not match, so it stops the bootstrap.
        fpr=$(gpg --show-keys --with-colons "${work}/mise.pub" | awk -F: '/^fpr:/ {print $10; exit}')
        if [[ "$fpr" != "$key_fpr" ]]; then
            rm -rf "$work"
            log_error "mise signing key is ${fpr}, expected ${key_fpr} — refusing to install"
            exit 1
        fi
        mkdir -m 700 "${work}/gnupg"
        GNUPGHOME="${work}/gnupg" gpg --quiet --import "${work}/mise.pub"
        # Require GOODSIG in the status output: gpg's exit code alone accepts
        # a good signature from an expired key.
        status=$(GNUPGHOME="${work}/gnupg" gpg --status-fd 3 \
            --output "${work}/verified.txt" --decrypt "${work}/SHASUMS256.asc" \
            3>&1 1>/dev/null 2>/dev/null || true)
        if ! grep -q '^\[GNUPG:\] GOODSIG' <<< "$status" \
            || ! grep -q " ./${asset}\$" "${work}/verified.txt" \
            || ! (cd "$work" && grep " ./${asset}\$" verified.txt | sha256sum -c -); then
            rm -rf "$work"
            log_error "mise ${version} failed signature or checksum verification — refusing to install"
            exit 1
        fi

        tar -xzf "${work}/${asset}" -C "$work"
        mkdir -p "${HOME}/.local/bin"
        install -m 755 "${work}/mise/bin/mise" "${HOME}/.local/bin/mise"
        rm -rf "$work"
        log_info "mise ${version} installed (signature verified)"
    }

    log_info "Installing mise (version manager)..."
    if ! command -v mise &>/dev/null; then
        install_mise_verified
    else
        log_info "mise already installed"
    fi

    log_info "Ubuntu modern tools installed successfully!"
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
