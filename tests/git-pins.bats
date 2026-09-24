#!/usr/bin/env bats
# Tests for install/common/sync-git-pins.sh, using local repositories in place
# of GitHub so no network is needed.

SYNC="${BATS_TEST_DIRNAME}/../install/common/sync-git-pins.sh"

setup() {
    TEST_DIR=$(mktemp -d)
    # A private HOME keeps the developer's own git config (signing, hooks) and
    # dotfiles out of the test.
    export HOME="${TEST_DIR}/home"
    mkdir -p "$HOME"
    unset XDG_CONFIG_HOME
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_PINS_URL_BASE="file://${TEST_DIR}/upstream"
    export GIT_PINS_FILE="${TEST_DIR}/pins"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# upstream <owner/name>: create an upstream repository serving fetch-by-SHA,
# as GitHub does.
upstream() {
    local path="${TEST_DIR}/upstream/$1"
    mkdir -p "$path"
    git -C "$path" init --quiet
    git -C "$path" config uploadpack.allowAnySHA1InWant true
}

# commit_to <owner/name> <content>: commit <content> to file.txt, print the SHA.
commit_to() {
    local path="${TEST_DIR}/upstream/$1"
    echo "$2" > "${path}/file.txt"
    git -C "$path" add file.txt
    git -C "$path" -c user.name=test -c user.email=test@example.com commit --quiet -m "$2"
    git -C "$path" rev-parse HEAD
}

pins() {
    printf '%s\n' "$@" > "$GIT_PINS_FILE"
}

plugin_dir() {
    echo "${HOME}/.oh-my-zsh/custom/plugins/$1"
}

@test "fresh install checks out the pinned commit, not the upstream tip" {
    upstream owner/plug
    local first
    first=$(commit_to owner/plug one)
    commit_to owner/plug two > /dev/null
    pins "zsh-plugin plug owner/plug ${first}"

    run "$SYNC"

    [[ "$status" -eq 0 ]]
    [[ "$(git -C "$(plugin_dir plug)" rev-parse HEAD)" == "$first" ]]
    [[ "$(cat "$(plugin_dir plug)/file.txt")" == "one" ]]
}

@test "moving the pin moves an existing checkout" {
    upstream owner/plug
    local first second
    first=$(commit_to owner/plug one)
    second=$(commit_to owner/plug two)
    pins "zsh-plugin plug owner/plug ${first}"
    "$SYNC"

    pins "zsh-plugin plug owner/plug ${second}"
    run "$SYNC"

    [[ "$status" -eq 0 ]]
    [[ "$(git -C "$(plugin_dir plug)" rev-parse HEAD)" == "$second" ]]
}

@test "a checkout already at its pin is left alone" {
    upstream owner/plug
    local first
    first=$(commit_to owner/plug one)
    pins "zsh-plugin plug owner/plug ${first}"
    "$SYNC"

    run "$SYNC"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"plug: at ${first:0:12}"* ]]
}

@test "a checkout cloned from a different repository is refused" {
    upstream owner/plug
    upstream someone-else/plug
    local pinned impostor
    pinned=$(commit_to owner/plug one)
    impostor=$(commit_to someone-else/plug evil)
    mkdir -p "$(dirname "$(plugin_dir plug)")"
    git clone --quiet "${TEST_DIR}/upstream/someone-else/plug" "$(plugin_dir plug)"
    pins "zsh-plugin plug owner/plug ${pinned}"

    run "$SYNC"

    [[ "$status" -eq 1 ]]
    [[ "$output" == *"expected ${GIT_PINS_URL_BASE}/owner/plug"* ]]
    [[ "$(git -C "$(plugin_dir plug)" rev-parse HEAD)" == "$impostor" ]]
}

@test "local edits block the checkout instead of being overwritten" {
    upstream owner/plug
    local first second
    first=$(commit_to owner/plug one)
    second=$(commit_to owner/plug two)
    pins "zsh-plugin plug owner/plug ${first}"
    "$SYNC"
    echo "my local tweak" > "$(plugin_dir plug)/file.txt"

    pins "zsh-plugin plug owner/plug ${second}"
    run "$SYNC"

    [[ "$status" -eq 1 ]]
    [[ "$(cat "$(plugin_dir plug)/file.txt")" == "my local tweak" ]]
    [[ "$(git -C "$(plugin_dir plug)" rev-parse HEAD)" == "$first" ]]
}

@test "oh-my-zsh is installed before its plugins, whatever the file order" {
    upstream ohmyzsh/ohmyzsh
    upstream owner/plug
    local omz plug
    omz=$(commit_to ohmyzsh/ohmyzsh core)
    plug=$(commit_to owner/plug one)
    pins "zsh-plugin plug owner/plug ${plug}" "omz oh-my-zsh ohmyzsh/ohmyzsh ${omz}"

    run "$SYNC"

    [[ "$status" -eq 0 ]]
    [[ "$(git -C "${HOME}/.oh-my-zsh" rev-parse HEAD)" == "$omz" ]]
    [[ "$(git -C "$(plugin_dir plug)" rev-parse HEAD)" == "$plug" ]]
}

@test "vim plugins go into the native package directory" {
    upstream owner/vimplug
    local pinned
    pinned=$(commit_to owner/vimplug one)
    pins "vim-plugin vimplug owner/vimplug ${pinned}"

    run "$SYNC"

    [[ "$status" -eq 0 ]]
    [[ "$(git -C "${HOME}/.vim/pack/plugins/start/vimplug" rev-parse HEAD)" == "$pinned" ]]
}

@test "an unset pin is reported and the rest still sync" {
    upstream owner/plug
    local pinned
    pinned=$(commit_to owner/plug one)
    pins "# comment lines are ignored" \
         "zsh-plugin unset owner/unset 0000000000000000000000000000000000000000" \
         "zsh-plugin plug owner/plug ${pinned}"

    run "$SYNC"

    [[ "$status" -eq 1 ]]
    [[ "$output" == *"unset: no commit pinned yet"* ]]
    [[ "$(git -C "$(plugin_dir plug)" rev-parse HEAD)" == "$pinned" ]]
}
