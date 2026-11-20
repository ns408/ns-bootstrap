#!/usr/bin/env bats
# The work profile in bootstrap.sh: macOS only, remembered, strict about
# Homebrew, keeping the files already on the Mac, and stopping before secrets
# and git hooks.
#
# Every run has a throwaway HOME, stubs for brew, launchctl, dseditgroup and
# sudo first on PATH, an empty pin list (nothing is cloned) and an empty /etc
# stand-in, so even a broken guard cannot touch this machine.

setup() {
    [[ "$OSTYPE" == darwin* ]] || skip "the work profile is macOS only"
    ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    TEST_HOME=$(mktemp -d)
    STUBS="${TEST_HOME}/stubs"
    BREW_PREFIX="${TEST_HOME}/brew"
    STUB_LOG="${TEST_HOME}/stub.log"
    mkdir -p "$STUBS" "$BREW_PREFIX" "${TEST_HOME}/etc"
    : > "${TEST_HOME}/no-pins"
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
        GIT_PINS_FILE="${TEST_HOME}/no-pins" NS_BOOTSTRAP_ETC_DIR="${TEST_HOME}/etc" \
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
    [[ -z "$(find "$TEST_HOME" -mindepth 1 -maxdepth 1 ! -name stubs ! -name brew ! -name stub.log ! -name etc ! -name no-pins)" ]]
}

@test "a real work run installs Brewfile.work only, remembers work, and completes" {
    bootstrap --profile work --yes
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Skipping the work git identity: set NS_BOOTSTRAP_GIT_NAME and NS_BOOTSTRAP_GIT_EMAIL"* ]]
    [[ "$output" == *"=== Bootstrap Complete! ==="* ]]
    grep -qx "brew bundle --file=${ROOT}/packages/Brewfile.work --verbose" "$STUB_LOG"
    grep -qx "brew analytics off" "$STUB_LOG"
    refute_grep -E -- '--cask|brew install' "$STUB_LOG"
    refute_grep -E '^(launchctl|sudo)' "$STUB_LOG"
    [[ "$(cat "${TEST_HOME}/.config/ns-bootstrap/profile")" == work ]]
    [[ ! -e "${TEST_HOME}/.gitconfig" ]]
}

@test "a work run sets the hooks path and chaining in ~/.config/git/config, not ~/.gitconfig" {
    printf '[credential]\n\thelper = company-helper\n' > "${TEST_HOME}/.gitconfig"
    before="$(cat "${TEST_HOME}/.gitconfig")"
    bootstrap --profile work --yes
    [[ "$status" -eq 0 ]]
    [[ "$(git config --file "${TEST_HOME}/.config/git/config" core.hooksPath)" == "${TEST_HOME}/.config/git/hooks" ]]
    [[ "$(git config --file "${TEST_HOME}/.config/git/config" ns-bootstrap.chainRepoHooks)" == true ]]
    [[ -x "${TEST_HOME}/.config/git/hooks/post-checkout" && -x "${TEST_HOME}/.config/git/hooks/pre-push" ]]
    [[ "$(cat "${TEST_HOME}/.gitconfig")" == "$before" ]]
}

@test "a hooks path IT already set is left alone, and ns-bootstrap's hooks are not installed" {
    printf '[core]\n\thooksPath = /opt/company/git-hooks\n' > "${TEST_HOME}/.gitconfig"
    bootstrap --profile work --dry-run
    [[ "$output" == *"core.hooksPath is already /opt/company/git-hooks; left alone"* ]]
    bootstrap --profile work --yes
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"core.hooksPath is already set to /opt/company/git-hooks"* ]]
    [[ -z "$(git config --file "${TEST_HOME}/.config/git/config" core.hooksPath 2>/dev/null)" ]]
    [[ ! -e "${TEST_HOME}/.config/git/hooks" ]]
}

@test "a chaining choice already made is kept" {
    mkdir -p "${TEST_HOME}/.config/git"
    printf '[ns-bootstrap]\n\tchainRepoHooks = false\n' > "${TEST_HOME}/.config/git/config"
    bootstrap --profile work --yes
    [[ "$status" -eq 0 ]]
    [[ "$(git config --file "${TEST_HOME}/.config/git/config" --get-all ns-bootstrap.chainRepoHooks)" == false ]]
}

@test "a work run keeps the company's shell, npm and pip files, sourcing ns-bootstrap from the top" {
    printf '# IT\nexport HTTPS_PROXY=http://proxy.example:8080\n' > "${TEST_HOME}/.zshrc"
    chmod 640 "${TEST_HOME}/.zshrc"
    printf 'registry=https://npm.example.com/\n' > "${TEST_HOME}/.npmrc"
    mkdir -p "${TEST_HOME}/.config/pip"
    printf '[global]\nindex-url = https://pypi.example.com/simple\n' > "${TEST_HOME}/.config/pip/pip.conf"
    bootstrap --profile work --yes
    [[ "$status" -eq 0 ]]
    [[ "$(head -1 "${TEST_HOME}/.zshrc")" == "# >>> ns-bootstrap >>>" ]]
    grep -qxF "[[ -f \"${ROOT}/dotfiles/shell/.zshrc\" ]] && source \"${ROOT}/dotfiles/shell/.zshrc\"" "${TEST_HOME}/.zshrc"
    [[ "$(tail -2 "${TEST_HOME}/.zshrc")" == $'# IT\nexport HTTPS_PROXY=http://proxy.example:8080' ]]
    [[ "$(stat -f %Lp "${TEST_HOME}/.zshrc")" == 640 ]]
    cmp "${TEST_HOME}"/.dotfiles-backup/*/.zshrc <(printf '# IT\nexport HTTPS_PROXY=http://proxy.example:8080\n')
    grep -qF "source \"${ROOT}/dotfiles/shell/.zprofile\"" "${TEST_HOME}/.zprofile"
    [[ ! -L "${TEST_HOME}/.npmrc" ]] && grep -qx 'registry=https://npm.example.com/' "${TEST_HOME}/.npmrc"
    grep -q 'pypi.example.com' "${TEST_HOME}/.config/pip/pip.conf"
    [[ "$(readlink "${TEST_HOME}/.vimrc")" == "${ROOT}/dotfiles/vim/.vimrc" ]]
}

@test "a work run with the name and email set writes the work identity and leaves ~/.gitconfig alone" {
    printf '[credential]\n\thelper = company-helper\n' > "${TEST_HOME}/.gitconfig"
    before="$(cat "${TEST_HOME}/.gitconfig")"
    NS_BOOTSTRAP_GIT_NAME="Example Person" NS_BOOTSTRAP_GIT_EMAIL="person@work.example.com" bootstrap --profile work --yes
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Work git identity ready"* ]]
    [[ "$(git config --file "${TEST_HOME}/.config/ns-bootstrap/gitconfig" user.email)" == person@work.example.com ]]
    [[ "$(cat "${TEST_HOME}/.gitconfig")" == "$before" ]]
    # shellcheck disable=SC2088  # the literal ~ is what the include holds
    [[ "$(git config --file "${TEST_HOME}/.config/git/config" --get-all include.path)" == "~/.config/ns-bootstrap/gitconfig" ]]
}

@test "with no npm or pip config, a work run copies them in as files you own" {
    bootstrap --profile work --yes
    [[ "$status" -eq 0 ]]
    [[ -f "${TEST_HOME}/.npmrc" && ! -L "${TEST_HOME}/.npmrc" ]]
    cmp "${TEST_HOME}/.npmrc" "${ROOT}/dotfiles/npm/.npmrc"
    [[ -f "${TEST_HOME}/.config/pip/pip.conf" && ! -L "${TEST_HOME}/.config/pip/pip.conf" ]]
}

@test "a second work run changes nothing" {
    printf 'export EDITOR=nano\n' > "${TEST_HOME}/.zshrc"
    bootstrap --profile work --yes
    before="$(cat "${TEST_HOME}/.zshrc" "${TEST_HOME}/.zprofile")"
    bootstrap --profile work --yes
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Already sourced: ${TEST_HOME}/.zshrc"* ]]
    [[ "$(cat "${TEST_HOME}/.zshrc" "${TEST_HOME}/.zprofile")" == "$before" ]]
    [[ "$(find "${TEST_HOME}/.dotfiles-backup" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" == 1 ]]
    [[ "$output" != *"[WARN]"* ]]
}

@test "a dotfile already there is kept on a work Mac" {
    echo 'set nocompatible' > "${TEST_HOME}/.vimrc"
    bootstrap --profile work --yes
    [[ "$status" -eq 0 ]]
    [[ ! -L "${TEST_HOME}/.vimrc" ]] && grep -qx 'set nocompatible' "${TEST_HOME}/.vimrc"
}

@test "--relink on a work Mac points the block at the repo's new place and keeps the rest" {
    mkdir -p "${TEST_HOME}/.config/ns-bootstrap"
    echo work > "${TEST_HOME}/.config/ns-bootstrap/profile"
    printf '%s\n' '# >>> ns-bootstrap >>>' '[[ -f "/old/place/dotfiles/shell/.zshrc" ]] && source "/old/place/dotfiles/shell/.zshrc"' \
        '# <<< ns-bootstrap <<<' '' 'export EDITOR=nano' > "${TEST_HOME}/.zshrc"
    bootstrap --relink
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Relink complete"* ]]
    grep -qF "source \"${ROOT}/dotfiles/shell/.zshrc\"" "${TEST_HOME}/.zshrc"
    refute_grep -F "/old/place" "${TEST_HOME}/.zshrc"
    [[ "$(tail -1 "${TEST_HOME}/.zshrc")" == "export EDITOR=nano" ]]
    [[ "$(grep -c '^# >>> ns-bootstrap >>>$' "${TEST_HOME}/.zshrc")" == 1 ]]
}

@test "the work dry run names settings both sides set, never their values" {
    printf 'export EDITOR=secret-editor-value\nalias g="git status"\n' > "${TEST_HOME}/.zshrc"
    printf 'export LANG=en_GB.UTF-8\n' > "${TEST_HOME}/etc/zprofile"
    bootstrap --profile work --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"EDITOR: ~/.zshrc runs later, so its value wins"* ]]
    [[ "$output" == *"alias g: ~/.zshrc runs later, so its value wins"* ]]
    [[ "$output" == *"LANG: ${TEST_HOME}/etc/zprofile runs earlier, so ns-bootstrap's value wins"* || "$output" == *"LANG: ~/etc/zprofile runs earlier, so ns-bootstrap's value wins"* ]]
    [[ "$output" != *"secret-editor-value"* && "$output" != *"en_GB"* ]]
    [[ "$output" == *"~/.zshrc: add the ns-bootstrap block at the top; your lines stay, after it"* ]]
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

@test "work with --dotfiles-only installs nothing but still sets up the dotfiles" {
    bootstrap --dotfiles-only --profile work --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Would install: nothing (--dotfiles-only)"* ]]
    bootstrap --dotfiles-only --profile work --yes
    [[ "$status" -eq 0 ]]
    [[ ! -e "$STUB_LOG" ]] || refute_grep 'brew bundle' "$STUB_LOG"
    grep -qxF '# >>> ns-bootstrap >>>' "${TEST_HOME}/.zshrc"
    [[ ! -e "${TEST_HOME}/.gitconfig" ]]
    [[ "$(cat "${TEST_HOME}/.config/ns-bootstrap/profile")" == work ]]
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
