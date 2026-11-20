#!/usr/bin/env bats
# The work profile in bootstrap.sh: macOS only, remembered, strict about
# Homebrew, and stopping before dotfiles, git hooks and secrets.
#
# Every run has a throwaway HOME and stubs for brew, launchctl, dseditgroup
# and sudo first on PATH, so even a broken guard cannot touch this machine.

setup() {
    [[ "$OSTYPE" == darwin* ]] || skip "the work profile is macOS only"
    ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    TEST_HOME=$(mktemp -d)
    STUBS="${TEST_HOME}/stubs"
    BREW_PREFIX="${TEST_HOME}/brew"
    STUB_LOG="${TEST_HOME}/stub.log"
    mkdir -p "$STUBS" "$BREW_PREFIX"
    cat > "${STUBS}/brew" <<'EOF'
#!/usr/bin/env bash
echo "brew $*" >> "$STUB_LOG"
case "$1" in
    --prefix) echo "$BREW_PREFIX" ;;
    help|list) exit 1 ;;
esac
exit 0
EOF
    for cmd in launchctl dseditgroup sudo; do
        printf '#!/usr/bin/env bash\necho "%s $*" >> "$STUB_LOG"\nexit 1\n' "$cmd" > "${STUBS}/${cmd}"
    done
    chmod 755 "$STUBS"/*
    export STUB_LOG BREW_PREFIX
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
    [[ -n "${TEST_HOME:-}" ]] && rm -rf "$TEST_HOME"
}

bootstrap() {
    run env -u NONINTERACTIVE HOME="$TEST_HOME" PATH="${STUBS}:${PATH}" \
        "${ROOT}/install/bootstrap.sh" "$@" < /dev/null
}

normalised() {
    printf '%s\n' "$output" \
        | sed -E $'s/\x1b\\[[0-9;]*m//g' \
        | sed -e "s|${ROOT}|@ROOT@|g" -e "s|${TEST_HOME}|@HOME@|g" -E -e 's/\([0-9]+ packages\)/(N packages)/'
}

@test "work dry run matches its golden" {
    bootstrap --profile work --dry-run
    [[ "$status" -eq 0 ]]
    diff "${BATS_TEST_DIRNAME}/fixtures/dry-run.work.macos.golden" <(normalised)
    [[ ! -e "$STUB_LOG" ]] || refute_grep -vx 'brew --prefix' "$STUB_LOG"
}

@test "work dry run reports a Homebrew that belongs to another account" {
    BREW_PREFIX=/ bootstrap --profile work --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Homebrew: a real run would stop here."* ]]
    [[ "$output" == *"belongs to 'root', so IT probably manages it"* ]]
}

@test "a real work run refuses a Homebrew that belongs to another account, changing nothing" {
    BREW_PREFIX=/ bootstrap --profile work --yes
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Nothing was changed."* ]]
    [[ "$output" != *"sudo chown"* ]]
    [[ -z "$(find "$TEST_HOME" -mindepth 1 -maxdepth 1 ! -name stubs ! -name brew ! -name stub.log)" ]]
}

@test "a real work run installs Brewfile.work only, remembers work, and stops before dotfiles" {
    bootstrap --profile work --yes
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Stopping before dotfiles, git hooks and secrets"* ]]
    grep -qx "brew bundle --file=${ROOT}/packages/Brewfile.work --verbose" "$STUB_LOG"
    grep -qx "brew analytics off" "$STUB_LOG"
    refute_grep -E -- '--cask|brew install' "$STUB_LOG"
    refute_grep -E '^(launchctl|sudo)' "$STUB_LOG"
    [[ "$(cat "${TEST_HOME}/.config/ns-bootstrap/profile")" == work ]]
    [[ ! -e "${TEST_HOME}/.zshrc" && ! -e "${TEST_HOME}/.gitconfig" && ! -e "${TEST_HOME}/.config/git" ]]
}

@test "a Brewfile of your own is installed after Brewfile.work" {
    mkdir -p "${TEST_HOME}/.config/ns-bootstrap"
    echo 'brew "jq"' > "${TEST_HOME}/company.Brewfile"
    echo 'NS_BOOTSTRAP_BREWFILE_LOCAL=~/company.Brewfile' > "${TEST_HOME}/.config/ns-bootstrap/settings"
    bootstrap --profile work --yes
    [[ "$status" -eq 0 ]]
    [[ "$(grep '^brew bundle' "$STUB_LOG")" == "brew bundle --file=${ROOT}/packages/Brewfile.work --verbose"$'\n'"brew bundle --file=${TEST_HOME}/company.Brewfile --verbose" ]]
}

@test "a plain run on a Mac remembered as work resolves to work" {
    mkdir -p "${TEST_HOME}/.config/ns-bootstrap"
    echo work > "${TEST_HOME}/.config/ns-bootstrap/profile"
    bootstrap --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Profile: work (remembered in"* ]]
    [[ "$output" == *"=== Dry Run Preview (work) ==="* ]]
}

@test "a personal profile is refused on a Mac remembered as work" {
    mkdir -p "${TEST_HOME}/.config/ns-bootstrap"
    echo work > "${TEST_HOME}/.config/ns-bootstrap/profile"
    bootstrap --profile minimal --dry-run
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"would install personal packages on it"* ]]
}

@test "work with --dotfiles-only previews nothing to install and does nothing for real" {
    bootstrap --dotfiles-only --profile work --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Would install: nothing (--dotfiles-only)"* ]]
    bootstrap --dotfiles-only --profile work --yes
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Nothing to do yet for --dotfiles-only --profile work"* ]]
    [[ ! -e "${TEST_HOME}/.zshrc" && ! -e "${TEST_HOME}/.config/git" ]]
}

@test "extra apps switched on for work stop the run with status 2" {
    mkdir -p "${TEST_HOME}/.config/ns-bootstrap"
    echo 'NS_BOOTSTRAP_EXTRA_APPS=on' > "${TEST_HOME}/.config/ns-bootstrap/settings"
    bootstrap --profile work --dry-run
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"cannot be on for the work profile"* ]]
}

@test "a bad setting stops a personal dry run too" {
    mkdir -p "${TEST_HOME}/.config/ns-bootstrap"
    echo 'NS_BOOTSTRAP_DAILY_UPDATE=sometimes' > "${TEST_HOME}/.config/ns-bootstrap/settings"
    bootstrap --profile minimal --dry-run
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"NS_BOOTSTRAP_DAILY_UPDATE must be on or off"* ]]
}
