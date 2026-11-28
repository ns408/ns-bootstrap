#!/usr/bin/env bats
# Tests for install/lib/common.sh

setup() {
    # Source the library under test
    source "${BATS_TEST_DIRNAME}/../install/lib/common.sh"
}

# === Logging functions ===

@test "log_info outputs [INFO] prefix" {
    run log_info "test message"
    [[ "$output" == *"[INFO]"* ]]
    [[ "$output" == *"test message"* ]]
}

@test "log_warn outputs [WARN] prefix" {
    run log_warn "warning message"
    [[ "$output" == *"[WARN]"* ]]
    [[ "$output" == *"warning message"* ]]
}

@test "log_error outputs [ERROR] prefix" {
    run log_error "error message"
    [[ "$output" == *"[ERROR]"* ]]
    [[ "$output" == *"error message"* ]]
}

@test "log_step outputs ==> prefix" {
    run log_step "step message"
    [[ "$output" == *"==> step message"* ]]
}

# === OS Detection ===

@test "detect_os sets OS variable on macOS" {
    if [[ "$OSTYPE" != "darwin"* ]]; then
        skip "Only runs on macOS"
    fi
    detect_os
    [[ "$OS" == "macos" ]]
    [[ "$SHELL_NAME" == "zsh" ]]
    [[ "$PKG_MGR" == "brew" ]]
}

@test "detect_os sets OS variable on Ubuntu" {
    if [[ ! -f /etc/os-release ]] || ! grep -q 'ID=ubuntu' /etc/os-release; then
        skip "Only runs on Ubuntu"
    fi
    detect_os
    [[ "$OS" == "ubuntu" ]]
    [[ "$SHELL_NAME" == "bash" ]]
    [[ "$PKG_MGR" == "apt" ]]
}

# === Brewfile trust ===

# A stand-in brew that logs each call; `brew help trust` succeeds unless
# NO_TRUST is set (Homebrew before 6), and `brew trust` fails for FAIL_TRUST.
trust_stub() {
    STUB_DIR=$(mktemp -d)
    cat > "${STUB_DIR}/brew" <<'BREW'
#!/usr/bin/env bash
echo "$*" >> "${STUB_DIR}/calls"
[[ "$1 $2" == "help trust" && -n "${NO_TRUST:-}" ]] && exit 1
[[ "$1" == trust && "$3" == "${FAIL_TRUST:-}" ]] && exit 1
exit 0
BREW
    chmod +x "${STUB_DIR}/brew"
    export STUB_DIR PATH="${STUB_DIR}:${PATH}"
    BREWFILE="${STUB_DIR}/Brewfile"
    cat > "$BREWFILE" <<'BF'
tap "owner/tap"
tap "other/tap"
# brew "owner/tap/commented", trusted: true
brew "jq"
brew "owner/tap/tool", trusted: true
brew "other/tap/untrusted"
cask "owner/tap/app", trusted: true
BF
}

@test "trust_brewfile_entries trusts each declared entry, never a whole tap" {
    trust_stub
    run trust_brewfile_entries "$BREWFILE"
    [[ "$status" -eq 0 ]] || { echo "$output"; false; }
    run grep -E '^(tap|trust)' "${STUB_DIR}/calls"
    [[ "$output" == "tap owner/tap
tap other/tap
trust --formula owner/tap/tool
trust --cask owner/tap/app" ]] || { cat "${STUB_DIR}/calls"; false; }
    rm -rf "$STUB_DIR"
}

@test "trust_brewfile_entries does nothing on a Homebrew without brew trust" {
    trust_stub
    NO_TRUST=1 run trust_brewfile_entries "$BREWFILE"
    [[ "$status" -eq 0 ]]
    [[ "$(cat "${STUB_DIR}/calls")" == "help trust" ]] || { cat "${STUB_DIR}/calls"; false; }
    rm -rf "$STUB_DIR"
}

@test "trust_brewfile_entries warns about an entry it cannot trust and carries on" {
    trust_stub
    FAIL_TRUST=owner/tap/tool run trust_brewfile_entries "$BREWFILE"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[WARN]"*"owner/tap/tool"* ]] || { echo "$output"; false; }
    grep -qx 'trust --cask owner/tap/app' "${STUB_DIR}/calls"
    rm -rf "$STUB_DIR"
}
