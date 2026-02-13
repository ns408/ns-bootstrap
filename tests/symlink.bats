#!/usr/bin/env bats
# Tests for symlink_file function from bootstrap.sh

setup() {
    # Create temp directory for each test
    TEST_DIR=$(mktemp -d)
    BACKUP_DIR="${TEST_DIR}/backups/$(date +%Y%m%d%H%M%S)"
    BACKUP_CREATED=false

    # Source logging functions
    source "${BATS_TEST_DIRNAME}/../install/lib/common.sh"

    # Define symlink_file (extracted from bootstrap.sh)
    symlink_file() {
        local src="$1"
        local dest="$2"

        if [[ -L "$dest" ]] && [[ "$(readlink "$dest")" == "$src" ]]; then
            return 0
        fi

        if [[ -e "$dest" ]] && [[ ! -L "$dest" ]]; then
            if [[ "$BACKUP_CREATED" == false ]]; then
                mkdir -p "$BACKUP_DIR"
                BACKUP_CREATED=true
            fi
            local backup_name
            backup_name=$(basename "$dest")
            mv "$dest" "${BACKUP_DIR}/${backup_name}"
        fi

        if [[ -L "$dest" ]]; then
            rm "$dest"
        fi

        ln -s "$src" "$dest"
    }
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

@test "symlink_file creates backup directory only when needed" {
    local src="${TEST_DIR}/source_file"
    local dest="${TEST_DIR}/dest_link"
    echo "content" > "$src"

    # No existing file to back up
    symlink_file "$src" "$dest"

    [[ "$BACKUP_CREATED" == false ]]
    [[ ! -d "$BACKUP_DIR" ]]
}
