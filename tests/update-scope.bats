#!/usr/bin/env bats
# NS_BOOTSTRAP_DAILY_SCOPE in the macOS update functions, and the daily
# script's off switch. brew, mas and softwareupdate are stubs; the settings
# library is the only part of the repo the functions can reach, so nothing
# real is upgraded or fetched.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    TEST_HOME=$(mktemp -d)
    export HOME="$TEST_HOME"
    export STUB_LOG="${TEST_HOME}/stub.log"
    mkdir -p "${TEST_HOME}/stubs" "${TEST_HOME}/repo/install/lib" "${HOME}/.config/ns-bootstrap"
    cp "${ROOT}/install/lib/settings.sh" "${TEST_HOME}/repo/install/lib/"
    export NS_BOOTSTRAP_DIR="${TEST_HOME}/repo"
    for cmd in brew mas softwareupdate; do
        printf '#!/usr/bin/env bash\necho "%s $*" >> "$STUB_LOG"\n' "$cmd" > "${TEST_HOME}/stubs/${cmd}"
    done
    chmod 755 "${TEST_HOME}"/stubs/*
    export PATH="${TEST_HOME}/stubs:${PATH}"
    unset NS_BOOTSTRAP_DAILY_SCOPE NS_BOOTSTRAP_DAILY_UPDATE
    source "${ROOT}/shell/platform/macos/update-system.sh"
}

# A plain "! cmd" line never fails a bats test (set -e ignores it), so
# assertions that something did not happen go through this.
refute_grep() {   # grep arguments; fails if grep finds a match
    if grep -q "$@"; then
        echo "unexpected match: $*"
        return 1
    fi
}

teardown() {
    rm -rf "$TEST_HOME"
}

@test "the daily update upgrades formulae and casks by default" {
    update-brew-daily > /dev/null
    grep -qx "brew upgrade" "$STUB_LOG"
    refute_grep "brew upgrade --formula" "$STUB_LOG"
}

@test "the daily update leaves casks alone when the scope is formulae" {
    echo 'NS_BOOTSTRAP_DAILY_SCOPE=formulae' > "${HOME}/.config/ns-bootstrap/settings"
    update-brew-daily > /dev/null
    grep -qx "brew upgrade --formula" "$STUB_LOG"
    refute_grep -x "brew upgrade" "$STUB_LOG"
    refute_grep -- "--cask" "$STUB_LOG"
}

@test "a Mac remembered as work defaults to formulae" {
    echo work > "${HOME}/.config/ns-bootstrap/profile"
    update-brew-daily > /dev/null
    grep -qx "brew upgrade --formula" "$STUB_LOG"
}

@test "update-my-system with scope formulae upgrades no casks or App Store apps" {
    echo 'NS_BOOTSTRAP_DAILY_SCOPE=formulae' > "${HOME}/.config/ns-bootstrap/settings"
    run update-my-system
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"leaving apps (casks, App Store, Microsoft) alone"* ]]
    grep -qx "brew upgrade --formula" "$STUB_LOG"
    refute_grep -- "--cask" "$STUB_LOG"
    refute_grep "^mas" "$STUB_LOG"
    grep -qx "softwareupdate -l" "$STUB_LOG"
}

@test "the daily script does nothing when the daily update is off" {
    [[ "$OSTYPE" == darwin* ]] || skip "the daily script only runs on macOS"
    echo 'NS_BOOTSTRAP_DAILY_UPDATE=off' > "${HOME}/.config/ns-bootstrap/settings"
    run bash "${ROOT}/scripts/scheduled-update-daily.sh"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"NS_BOOTSTRAP_DAILY_UPDATE=off; skipping"* ]]
    [[ ! -e "$STUB_LOG" ]]
}
