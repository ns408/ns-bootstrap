#!/usr/bin/env bats
# Tests for process_template (install/lib/template.sh)
#
# The goldens in tests/fixtures/ were rendered by the function as it stood in
# secrets/bootstrap-secrets.sh before it moved, with the inputs below. A change
# to either template, or to the function, must update them on purpose.

setup() {
    TEST_DIR=$(mktemp -d)
    ROOT="${BATS_TEST_DIRNAME}/.."
    FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
    source "${ROOT}/install/lib/common.sh"
    source "${ROOT}/install/lib/template.sh"

    HOME=/home/example
    GIT_NAME_PERSONAL="Example Person"
    GIT_EMAIL_PERSONAL="person@example.com"
    GIT_NAME_WORK="Example Person"
    GIT_EMAIL_WORK="person@work.example.com"
    GIT_SIGNING_KEY="ssh-ed25519 AAAAexamplepersonalkey"
    WORK_SIGNING_KEY="ssh-ed25519 AAAAexampleworkkey"
    WORK_GPG_SECTION=""
    # shellcheck disable=SC2088  # a literal ~ is what git includeIf expects
    WORK_REPO_DIR="~/work/"
    OP_SSH_SIGN_PATH="/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
    GIT_COMMIT_GPGSIGN="true"
    GIT_CREDENTIAL_HELPER="osxkeychain"
    DATA_DIR="/home/example/data"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "personal gitconfig renders exactly as before" {
    process_template "${ROOT}/dotfiles/git/.gitconfig.template" "${TEST_DIR}/gitconfig"
    diff "${FIXTURES}/gitconfig.personal.golden" "${TEST_DIR}/gitconfig"
}

@test "work gitconfig renders exactly as before" {
    process_template "${ROOT}/dotfiles/git/.gitconfig-work.template" "${TEST_DIR}/gitconfig-work"
    diff "${FIXTURES}/gitconfig-work.golden" "${TEST_DIR}/gitconfig-work"
}

@test "unset signing and credential values fall back to false and store" {
    unset GIT_COMMIT_GPGSIGN GIT_CREDENTIAL_HELPER
    process_template "${ROOT}/dotfiles/git/.gitconfig.template" "${TEST_DIR}/gitconfig"
    [[ "$(grep -c '^    gpgsign = false$' "${TEST_DIR}/gitconfig")" -eq 2 ]]
    grep -qx '    helper = store' "${TEST_DIR}/gitconfig"
}

@test "an existing output file is backed up before it is replaced" {
    HOME="$TEST_DIR"
    echo "old content" > "${TEST_DIR}/gitconfig"
    process_template "${ROOT}/dotfiles/git/.gitconfig-work.template" "${TEST_DIR}/gitconfig"
    grep -qx "old content" "${TEST_DIR}"/.dotfiles-backup/*/gitconfig
    grep -qx "    email = person@work.example.com" "${TEST_DIR}/gitconfig"
}

@test "a missing template returns 1 and writes nothing" {
    run process_template "${TEST_DIR}/no-such.template" "${TEST_DIR}/out"
    [[ "$status" -eq 1 ]]
    [[ ! -e "${TEST_DIR}/out" ]]
}
