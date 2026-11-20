#!/usr/bin/env bats
# Real bootstrap.sh --dotfiles-only runs against a throwaway HOME: git writes
# only there, the pin list is empty so nothing is cloned, and --yes skips the
# secrets prompt.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    TEST_HOME=$(mktemp -d)
    : > "${TEST_HOME}/no-pins"
}

teardown() {
    rm -rf "$TEST_HOME"
}

dotfiles_run() {
    run env -u NONINTERACTIVE HOME="$TEST_HOME" GIT_PINS_FILE="${TEST_HOME}/no-pins" \
        GIT_CONFIG_NOSYSTEM=1 "${ROOT}/install/bootstrap.sh" --dotfiles-only --yes < /dev/null
}

@test "an existing ~/.npmrc of your own is kept" {
    printf 'registry=https://npm.example.com/\n' > "${TEST_HOME}/.npmrc"
    dotfiles_run
    [[ "$status" -eq 0 ]]
    [[ ! -L "${TEST_HOME}/.npmrc" ]]
    grep -qx 'registry=https://npm.example.com/' "${TEST_HOME}/.npmrc"
    [[ "$output" == *"Keeping your ~/.npmrc"* ]]
}

@test "with no ~/.npmrc, ns-bootstrap's is linked as before" {
    dotfiles_run
    [[ "$status" -eq 0 ]]
    [[ "$(readlink "${TEST_HOME}/.npmrc")" == "${ROOT}/dotfiles/npm/.npmrc" ]]
}
