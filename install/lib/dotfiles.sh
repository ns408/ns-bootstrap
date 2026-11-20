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

# --- Work profile: files on a company Mac stay where they are -------------
#
# ~/.zshrc and ~/.zprofile get one marked block at the top that sources
# ns-bootstrap's version; the lines already there run after it, so where both
# set something, theirs wins. Deleting the block undoes it. Other dotfiles are
# linked only where none exists yet, and npm and pip configs are copied in, so
# a tool that edits them edits your file, not the repo.

NS_BLOCK_BEGIN='# >>> ns-bootstrap >>>'
NS_BLOCK_END='# <<< ns-bootstrap <<<'

_ns_block() {          # SRC: the block that sources SRC
    printf '%s\n' "$NS_BLOCK_BEGIN" \
        "# Added by ns-bootstrap. Lines after this block run later, so they win." \
        "[[ -f \"$1\" ]] && source \"$1\"" \
        "$NS_BLOCK_END"
}

_ns_backup_copy() {    # FILE: copy FILE into this run's BACKUP_DIR
    if [[ "$BACKUP_CREATED" == false ]]; then
        mkdir -p "$BACKUP_DIR"
        BACKUP_CREATED=true
        log_info "Backup directory: ${BACKUP_DIR}"
    fi
    cp -p "$1" "${BACKUP_DIR}/$(basename "$1")"
    log_info "Backed up ${1} -> ${BACKUP_DIR}/$(basename "$1")"
}

# What source_block would do to DEST: create, insert, update, current,
# replace-link (DEST is ns-bootstrap's own symlink to SRC) or skip-link.
source_block_action() {    # DEST SRC
    local dest="$1" src="$2"
    if [[ -L "$dest" ]]; then
        [[ "$(readlink "$dest")" == "$src" ]] && echo replace-link || echo skip-link
    elif [[ ! -e "$dest" ]]; then
        echo create
    elif ! grep -qxF "$NS_BLOCK_BEGIN" "$dest"; then
        echo insert
    elif [[ "$(sed -n "\|^${NS_BLOCK_BEGIN}\$|,\|^${NS_BLOCK_END}\$|p" "$dest")" == "$(_ns_block "$src")" ]]; then
        echo current
    else
        echo update
    fi
}

source_block() {           # DEST SRC
    local dest="$1" src="$2" action tmp
    action="$(source_block_action "$dest" "$src")"
    case "$action" in
        current)
            log_info "Already sourced: ${dest} -> ${src}"
            return 0 ;;
        skip-link)
            log_warn "${dest} is a symlink to $(readlink "$dest"); left alone. To use ns-bootstrap's shell setup, add to its top:"
            _ns_block "$src" | sed 's/^/    /'
            return 0 ;;
    esac
    tmp="$(mktemp "${dest}.ns-bootstrap.XXXXXX")"
    case "$action" in
        create|replace-link)
            _ns_block "$src" > "$tmp" ;;
        insert)
            _ns_backup_copy "$dest"
            { _ns_block "$src"; echo ""; cat "$dest"; } > "$tmp" ;;
        update)
            _ns_backup_copy "$dest"
            # The block goes in through the environment: macOS awk refuses a
            # newline in a -v value.
            NS_BLOCK="$(_ns_block "$src")" awk -v begin="$NS_BLOCK_BEGIN" -v end="$NS_BLOCK_END" '
                $0 == begin { print ENVIRON["NS_BLOCK"]; skip = 1; next }
                skip && $0 == end { skip = 0; next }
                !skip { print }' "$dest" > "$tmp" ;;
    esac
    if [[ "$action" == replace-link ]]; then
        rm "$dest"
    fi
    if [[ -f "$dest" ]]; then
        cat "$tmp" > "$dest"    # rewrite in place: keeps the file's owner and mode
        rm -f "$tmp"
    else
        mv "$tmp" "$dest"
    fi
    LINKS_CHANGED=$((LINKS_CHANGED + 1))
    log_info "Sourced from ${dest} (${action}): ${src}"
}

# DEST stays if it is a file of your own; otherwise it is linked as usual.
keep_or_link() {           # SRC DEST
    if [[ -e "$2" && ! -L "$2" ]]; then
        log_info "Keeping your ${2}"
    else
        symlink_file "$1" "$2"
    fi
}

# DEST stays if it exists; otherwise SRC is copied in as a file you own.
# ns-bootstrap's own old symlink to SRC is replaced by the copy.
keep_or_copy() {           # SRC DEST
    if [[ -L "$2" && "$(readlink "$2")" == "$1" ]]; then
        rm "$2"
    fi
    if [[ -e "$2" || -L "$2" ]]; then
        log_info "Keeping your ${2}"
    else
        mkdir -p "$(dirname "$2")"
        cp "$1" "$2"
        LINKS_CHANGED=$((LINKS_CHANGED + 1))
        log_info "Copied ${1} -> ${2} (yours to edit)"
    fi
}

# --- Conflict report ------------------------------------------------------

# Variable and alias names a shell file sets: "var NAME" or "alias NAME".
# Variables count when exported, or assigned at the top level (not indented,
# so not a function's own). Search paths are left out: they add up rather
# than replace each other.
shell_names() {            # FILE...
    sed -nE \
        -e 's/^[[:space:]]*export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)=.*/var \1/p' \
        -e 's/^([A-Za-z_][A-Za-z0-9_]*)\+?=.*/var \1/p' \
        -e 's/^[[:space:]]*alias[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*([^=[:space:]]+)=.*/alias \2/p' \
        "$@" 2>/dev/null \
        | grep -vxE 'var (PATH|path|FPATH|fpath|MANPATH|manpath|INFOPATH|cdpath|CDPATH)' \
        | LC_ALL=C sort -u
}

# Names set both by ns-bootstrap's shell files and by files already on this
# Mac, one per line: "NAME<TAB>FILE<TAB>WINNER". zsh reads, in order:
# /etc/zshenv, ~/.zshenv, /etc/zprofile, ~/.zprofile (ns-bootstrap's block
# first), /etc/zshrc, ~/.zshrc (block first). The later setting wins.
work_conflicts() {         # ROOT HOME [ETC]
    local root="$1" home="$2" etc="${3:-/etc}" tmp entry file shown order ours name kind
    tmp="$(mktemp -d)"
    shell_names "${root}/dotfiles/shell/.zprofile" > "${tmp}/profile"
    shell_names "${root}/dotfiles/shell/.zshrc" "${root}"/shell/*.sh "${root}"/shell/aliases/*.sh \
        "${root}"/shell/functions/*.sh "${root}"/shell/platform/macos/*.sh > "${tmp}/rc"
    LC_ALL=C sort -u "${tmp}/profile" "${tmp}/rc" > "${tmp}/ours"
    # file and its place in zsh's order; ns-bootstrap's .zprofile is 4, .zshrc 7
    for entry in "${etc}/zshenv:1" "${home}/.zshenv:2" "${etc}/zprofile:3" "${home}/.zprofile:5" \
                 "${etc}/zshrc:6" "${home}/.zshrc:8"; do
        file="${entry%:*}" order="${entry##*:}"
        [[ -f "$file" ]] || continue
        # ns-bootstrap's own symlink from an earlier run is not someone else's file
        [[ -L "$file" && "$(readlink "$file")" == "${root}"/* ]] && continue
        shown="${file/#"$home"/\~}"
        shell_names "$file" | LC_ALL=C comm -12 - "${tmp}/ours" | while read -r kind name; do
            if grep -qxF "${kind} ${name}" "${tmp}/rc"; then ours=7; else ours=4; fi
            [[ "$kind" == alias ]] && name="alias ${name}"
            if [[ "$order" -gt "$ours" ]]; then
                printf '%s\t%s\t%s\n' "$name" "$shown" theirs
            else
                printf '%s\t%s\t%s\n' "$name" "$shown" ns-bootstrap
            fi
        done
    done
    rm -rf "$tmp"
}
