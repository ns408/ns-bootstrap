#!/usr/bin/env bats
# install/lib/dotfiles.sh, work profile helpers: the marked source block,
# keep-or-link, keep-or-copy and the conflict report.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    TEST_DIR=$(mktemp -d)
    BACKUP_DIR="${TEST_DIR}/backup"
    BACKUP_CREATED=false
    LINKS_CHANGED=0
    source "${ROOT}/install/lib/common.sh"
    source "${ROOT}/install/lib/dotfiles.sh"
    SRC="${TEST_DIR}/repo/dotfiles/shell/.zshrc"
    mkdir -p "$(dirname "$SRC")"
    echo '# ns-bootstrap zshrc' > "$SRC"
    DEST="${TEST_DIR}/.zshrc"
}

# A plain "! cmd" line never fails a bats test (set -e ignores it).
refute_grep() {
    if grep -q "$@"; then
        echo "unexpected match: $*"
        return 1
    fi
}

teardown() {
    rm -rf "$TEST_DIR"
}

block_for() {
    printf '%s\n' '# >>> ns-bootstrap >>>' \
        '# Added by ns-bootstrap. Lines after this block run later, so they win.' \
        "[[ -f \"$1\" ]] && source \"$1\"" '# <<< ns-bootstrap <<<'
}

@test "a missing file is created holding only the block" {
    source_block "$DEST" "$SRC"
    diff <(block_for "$SRC") "$DEST"
    [[ "$BACKUP_CREATED" == false ]]
}

@test "the block goes on top, the lines already there follow, and the original is backed up" {
    printf 'export HTTPS_PROXY=http://proxy.example:8080\n' > "$DEST"
    chmod 640 "$DEST"
    source_block "$DEST" "$SRC"
    diff <(block_for "$SRC"; echo ""; echo 'export HTTPS_PROXY=http://proxy.example:8080') "$DEST"
    [[ "$(stat -f %Lp "$DEST" 2>/dev/null || stat -c %a "$DEST")" == 640 ]]
    grep -qx 'export HTTPS_PROXY=http://proxy.example:8080' "${BACKUP_DIR}/.zshrc"
    refute_grep -F 'ns-bootstrap' "${BACKUP_DIR}/.zshrc"
}

@test "a second run finds the block current and touches nothing" {
    printf 'export A=1\n' > "$DEST"
    source_block "$DEST" "$SRC"
    BACKUP_CREATED=false
    rm -rf "$BACKUP_DIR"
    before="$(cat "$DEST")"
    [[ "$(source_block_action "$DEST" "$SRC")" == current ]]
    source_block "$DEST" "$SRC"
    [[ "$(cat "$DEST")" == "$before" ]]
    [[ ! -e "$BACKUP_DIR" ]]
}

@test "a block for a moved repo is updated in place, wherever it now sits" {
    printf '%s\n' 'export FIRST=1' '# >>> ns-bootstrap >>>' 'source /old/.zshrc' '# <<< ns-bootstrap <<<' 'export LAST=1' > "$DEST"
    [[ "$(source_block_action "$DEST" "$SRC")" == update ]]
    source_block "$DEST" "$SRC"
    diff <(echo 'export FIRST=1'; block_for "$SRC"; echo 'export LAST=1') "$DEST"
}

@test "a file rewritten without the block gets it back" {
    printf 'export A=1\n' > "$DEST"
    source_block "$DEST" "$SRC"
    printf 'export B=2\n' > "$DEST"
    source_block "$DEST" "$SRC"
    diff <(block_for "$SRC"; echo ""; echo 'export B=2') "$DEST"
}

@test "ns-bootstrap's own old symlink becomes a file holding the block" {
    ln -s "$SRC" "$DEST"
    source_block "$DEST" "$SRC"
    [[ ! -L "$DEST" ]]
    diff <(block_for "$SRC") "$DEST"
    [[ "$(cat "$SRC")" == '# ns-bootstrap zshrc' ]]
}

@test "a symlink to somewhere else is left alone, with the block shown to add by hand" {
    echo 'managed' > "${TEST_DIR}/managed-zshrc"
    ln -s "${TEST_DIR}/managed-zshrc" "$DEST"
    run source_block "$DEST" "$SRC"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"left alone"* && "$output" == *"# >>> ns-bootstrap >>>"* ]]
    [[ "$(readlink "$DEST")" == "${TEST_DIR}/managed-zshrc" ]]
    [[ "$(cat "${TEST_DIR}/managed-zshrc")" == managed ]]
}

@test "keep_or_link keeps a file of your own and links where there is none" {
    echo mine > "${TEST_DIR}/.vimrc"
    keep_or_link "$SRC" "${TEST_DIR}/.vimrc"
    [[ ! -L "${TEST_DIR}/.vimrc" && "$(cat "${TEST_DIR}/.vimrc")" == mine ]]
    keep_or_link "$SRC" "${TEST_DIR}/.inputrc"
    [[ "$(readlink "${TEST_DIR}/.inputrc")" == "$SRC" ]]
}

@test "keep_or_copy keeps what is there, copies where nothing is, and replaces only its own symlink" {
    echo mine > "${TEST_DIR}/.npmrc"
    keep_or_copy "$SRC" "${TEST_DIR}/.npmrc"
    [[ "$(cat "${TEST_DIR}/.npmrc")" == mine ]]
    keep_or_copy "$SRC" "${TEST_DIR}/pip/pip.conf"
    [[ -f "${TEST_DIR}/pip/pip.conf" && ! -L "${TEST_DIR}/pip/pip.conf" ]]
    ln -s "$SRC" "${TEST_DIR}/old-link"
    keep_or_copy "$SRC" "${TEST_DIR}/old-link"
    [[ -f "${TEST_DIR}/old-link" && ! -L "${TEST_DIR}/old-link" ]]
    ln -s "${TEST_DIR}/.npmrc" "${TEST_DIR}/other-link"
    keep_or_copy "$SRC" "${TEST_DIR}/other-link"
    [[ "$(readlink "${TEST_DIR}/other-link")" == "${TEST_DIR}/.npmrc" ]]
}

@test "shell_names reads exports, top-level assignments and aliases, and skips function locals and search paths" {
    cat > "${TEST_DIR}/f" <<'EOF'
export EDITOR=vim
HISTSIZE=1000
alias ll='ls -l'
alias -g G='| grep'
export PATH="/x:$PATH"
path+=(/y)
f() {
    local inner=1
    helper=2
    export FROM_FUNCTION=1
}
# export COMMENTED=1
EOF
    [[ "$(shell_names "${TEST_DIR}/f")" == $'alias G\nalias ll\nvar EDITOR\nvar FROM_FUNCTION\nvar HISTSIZE' ]]
}

@test "work_conflicts says who wins by zsh's reading order" {
    local root="${TEST_DIR}/repo" home="${TEST_DIR}/home" etc="${TEST_DIR}/etc"
    mkdir -p "${root}/shell" "$home" "$etc"
    printf 'export EDITOR=vim\nexport LANG=C\n' > "${root}/dotfiles/shell/.zprofile"
    printf 'alias g=git\nHISTSIZE=1\n' > "${root}/dotfiles/shell/.zshrc"
    printf 'export LANG=x\n' > "${etc}/zprofile"           # before ns-bootstrap's .zprofile
    printf 'export EDITOR=x\nalias g=x\n' > "${etc}/zshrc"  # after .zprofile, before .zshrc
    printf 'HISTSIZE=2\n' > "${home}/.zshrc"                 # after everything
    printf 'export UNRELATED=1\n' > "${home}/.zprofile"
    run work_conflicts "$root" "$home" "$etc"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *$'LANG\t'"${etc}/zprofile"$'\tns-bootstrap'* ]]
    [[ "$output" == *$'EDITOR\t'"${etc}/zshrc"$'\ttheirs'* ]]
    [[ "$output" == *$'alias g\t'"${etc}/zshrc"$'\tns-bootstrap'* ]]
    [[ "$output" == *$'HISTSIZE\t~/.zshrc\ttheirs'* ]]
    [[ "$output" != *UNRELATED* ]]
}

@test "work_conflicts skips ns-bootstrap's own symlinks from an earlier run" {
    local home="${TEST_DIR}/home"
    mkdir -p "$home"
    ln -s "${ROOT}/dotfiles/shell/.zshrc" "${home}/.zshrc"
    run work_conflicts "$ROOT" "$home" "${TEST_DIR}/no-etc"
    [[ "$status" -eq 0 && -z "$output" ]]
}
