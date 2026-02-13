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
