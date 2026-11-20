#!/usr/bin/env bash
# Dotfile helpers for bootstrap.sh. Source after common.sh (needs log_info).
#
# symlink_file SRC DEST: point DEST at SRC, moving any real file at DEST into
# BACKUP_DIR first. The caller sets BACKUP_DIR, BACKUP_CREATED (false) and
# LINKS_CHANGED (0); this updates the last two.
# shellcheck disable=SC2034  # BACKUP_CREATED and LINKS_CHANGED are read by the caller

symlink_file() {
    local src="$1"
    local dest="$2"

    # Skip if symlink already points to correct target
    if [[ -L "$dest" ]] && [[ "$(readlink "$dest")" == "$src" ]]; then
        log_info "Already linked: ${dest} -> ${src}"
        return 0
    fi

    if [[ -e "$dest" ]] && [[ ! -L "$dest" ]]; then
        if [[ "$BACKUP_CREATED" == false ]]; then
            mkdir -p "$BACKUP_DIR"
            BACKUP_CREATED=true
            log_info "Backup directory: ${BACKUP_DIR}"
        fi
        local backup_name
        backup_name=$(basename "$dest")
        log_info "Backing up existing ${dest} -> ${BACKUP_DIR}/${backup_name}"
        mv "$dest" "${BACKUP_DIR}/${backup_name}"
    fi

    if [[ -L "$dest" ]]; then
        rm "$dest"
    fi

    ln -s "$src" "$dest"
    LINKS_CHANGED=$((LINKS_CHANGED + 1))
    log_info "Linked: ${dest} -> ${src}"
}
