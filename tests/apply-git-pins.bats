#!/usr/bin/env bats
# Tests for shell/apply-git-pins.zsh, the shell-start hook that applies pin
# bumps. It runs in a real zsh against a stand-in repository whose sync script
# only records that it was called.

setup() {
    TEST_DIR=$(mktemp -d)
    ROOT="${TEST_DIR}/root"
    mkdir -p "${ROOT}/shell" "${ROOT}/install/common" "${ROOT}/packages"
    cp "${BATS_TEST_DIRNAME}/../shell/apply-git-pins.zsh" "${ROOT}/shell/"
    export HOME="${TEST_DIR}/home"
    mkdir -p "$HOME"
    unset XDG_CACHE_HOME
    STATE="${HOME}/.cache/ns-bootstrap"
    export CALLS="${TEST_DIR}/calls"
    export STUB_EXIT=0

    # Honours the real script's contract: record the applied pins on success.
    cat > "${ROOT}/install/common/sync-git-pins.sh" <<'SYNC'
#!/usr/bin/env bash
echo called >> "$CALLS"
if [[ "$STUB_EXIT" -eq 0 ]]; then
    mkdir -p "${HOME}/.cache/ns-bootstrap"
    cp "$(dirname "$0")/../../packages/git-pins" "${HOME}/.cache/ns-bootstrap/git-pins.applied"
fi
exit "$STUB_EXIT"
SYNC
    echo "zsh-plugin plug owner/plug 1111111111111111111111111111111111111111" > "${ROOT}/packages/git-pins"
}

teardown() {
    rm -rf "$TEST_DIR"
}

start_shell() {
    run zsh -f -c "source '${ROOT}/shell/apply-git-pins.zsh'"
}

# minutes_ago <n>: a touch -t timestamp n minutes in the past (BSD and GNU).
minutes_ago() {
    zsh -fc "zmodload zsh/datetime; strftime %Y%m%d%H%M \$((EPOCHSECONDS - $1 * 60))"
}

calls() {
    [[ -f "$CALLS" ]] && wc -l < "$CALLS" | tr -d ' ' || echo 0
}

@test "an ordinary shell start with unchanged pins runs nothing and prints nothing" {
    mkdir -p "$STATE"
    cp "${ROOT}/packages/git-pins" "${STATE}/git-pins.applied"

    start_shell

    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
    [[ "$(calls)" -eq 0 ]]
}

@test "changed pins are applied once, then left alone" {
    start_shell
    [[ "$output" == *"pinned plugins changed, applying"* ]]
    [[ "$(calls)" -eq 1 ]]

    start_shell
    [[ -z "$output" ]]
    [[ "$(calls)" -eq 1 ]]
}

@test "a failed apply is retried within the hour, not on every shell" {
    export STUB_EXIT=1
    start_shell
    [[ "$output" == *"some pins were not applied"* ]]
    [[ "$(calls)" -eq 1 ]]

    start_shell
    [[ "$(calls)" -eq 1 ]]

    # An hour on, it tries again.
    touch -t "$(minutes_ago 70)" "${STATE}/git-pins.failed"
    start_shell
    [[ "$(calls)" -eq 2 ]]
}

@test "a second bump within the hour of a successful one is still applied" {
    start_shell
    [[ "$(calls)" -eq 1 ]]

    echo "zsh-plugin plug owner/plug 2222222222222222222222222222222222222222" > "${ROOT}/packages/git-pins"
    start_shell

    [[ "$output" == *"applying"* ]]
    [[ "$(calls)" -eq 2 ]]
}

@test "after a failure, a different pin list is tried straight away" {
    export STUB_EXIT=1
    start_shell
    [[ "$(calls)" -eq 1 ]]

    export STUB_EXIT=0
    echo "zsh-plugin plug owner/plug 2222222222222222222222222222222222222222" > "${ROOT}/packages/git-pins"
    start_shell

    [[ "$(calls)" -eq 2 ]]
    [[ ! -e "${STATE}/git-pins.failed" ]]
}

@test "a shell that finds another one applying leaves it to that shell" {
    mkdir -p "${STATE}/git-pins.lock"

    start_shell

    [[ "$(calls)" -eq 0 ]]
}

@test "a lock left behind by a killed shell expires after ten minutes" {
    mkdir -p "${STATE}/git-pins.lock"
    touch -t "$(minutes_ago 20)" "${STATE}/git-pins.lock"

    start_shell

    [[ "$(calls)" -eq 1 ]]
    [[ ! -e "${STATE}/git-pins.lock" ]]
}

@test "a checkout without a pin file does nothing" {
    rm "${ROOT}/packages/git-pins"

    start_shell

    [[ "$status" -eq 0 ]]
    [[ "$(calls)" -eq 0 ]]
}
