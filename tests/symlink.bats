#!/usr/bin/env bats
# Tests for symlink_file (install/lib/dotfiles.sh)

setup() {
    # Create temp directory for each test
    TEST_DIR=$(mktemp -d)
    BACKUP_DIR="${TEST_DIR}/backups/$(date +%Y%m%d%H%M%S)"
    BACKUP_CREATED=false
    LINKS_CHANGED=0

    # Source logging functions
    source "${BATS_TEST_DIRNAME}/../install/lib/common.sh"

    # The real function, not a copy
    source "${BATS_TEST_DIRNAME}/../install/lib/dotfiles.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "symlink_file creates symlink to source" {
    local src="${TEST_DIR}/source_file"
    local dest="${TEST_DIR}/dest_link"
    echo "content" > "$src"

    symlink_file "$src" "$dest"

    [[ -L "$dest" ]]
    [[ "$(readlink "$dest")" == "$src" ]]
}

@test "symlink_file skips when already correctly linked" {
    local src="${TEST_DIR}/source_file"
    local dest="${TEST_DIR}/dest_link"
    echo "content" > "$src"
    ln -s "$src" "$dest"

    run symlink_file "$src" "$dest"
    [[ "$status" -eq 0 ]]
    [[ "$(readlink "$dest")" == "$src" ]]
}

@test "symlink_file backs up existing regular file" {
    local src="${TEST_DIR}/source_file"
    local dest="${TEST_DIR}/dest_file"
    echo "new content" > "$src"
    echo "old content" > "$dest"

    symlink_file "$src" "$dest"

    # Dest should now be a symlink
    [[ -L "$dest" ]]
    [[ "$(readlink "$dest")" == "$src" ]]

    # Backup should exist with original content
    [[ -f "${BACKUP_DIR}/dest_file" ]]
    [[ "$(cat "${BACKUP_DIR}/dest_file")" == "old content" ]]
}

@test "symlink_file replaces incorrect symlink" {
    local src="${TEST_DIR}/source_file"
    local old_src="${TEST_DIR}/old_source"
    local dest="${TEST_DIR}/dest_link"
    echo "new" > "$src"
    echo "old" > "$old_src"
    ln -s "$old_src" "$dest"

    symlink_file "$src" "$dest"

    [[ -L "$dest" ]]
    [[ "$(readlink "$dest")" == "$src" ]]
}

@test "symlink_file repairs a dangling symlink" {
    # A moved repo leaves links pointing at a path that no longer exists. Tools
    # that create their config on first run (atuin) then fail with ENOENT,
    # because the create resolves to the vanished target, not to dest.
    local src="${TEST_DIR}/source_file"
    local dest="${TEST_DIR}/dest_link"
    echo "content" > "$src"
    ln -s "${TEST_DIR}/gone/source_file" "$dest"
    [[ ! -e "$dest" ]]

    symlink_file "$src" "$dest"

    [[ -L "$dest" ]]
    [[ -e "$dest" ]]
    [[ "$(readlink "$dest")" == "$src" ]]
    [[ "$LINKS_CHANGED" -eq 1 ]]
}

@test "symlink_file leaves the change counter alone when already linked" {
    local src="${TEST_DIR}/source_file"
    local dest="${TEST_DIR}/dest_link"
    echo "content" > "$src"
    ln -s "$src" "$dest"

    symlink_file "$src" "$dest"

    [[ "$LINKS_CHANGED" -eq 0 ]]
}

@test "symlink_file creates backup directory only when needed" {
    local src="${TEST_DIR}/source_file"
    local dest="${TEST_DIR}/dest_link"
    echo "content" > "$src"

    # No existing file to back up
    symlink_file "$src" "$dest"

    [[ "$BACKUP_CREATED" == false ]]
    [[ ! -d "$BACKUP_DIR" ]]
}
