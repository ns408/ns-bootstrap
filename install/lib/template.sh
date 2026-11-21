#!/usr/bin/env bash
# Template rendering for secrets/bootstrap-secrets.sh. The caller defines
# log_info and log_warn.
#
# process_template TEMPLATE OUTPUT: replace each known ${PLACEHOLDER} in
# TEMPLATE with the caller's variable of that name and write OUTPUT, backing up
# a real file at OUTPUT to ~/.dotfiles-backup/<timestamp>/ first.

process_template() {
    local template_file="$1"
    local output_file="$2"

    if [[ ! -f "$template_file" ]]; then
        log_warn "Template file not found: $template_file"
        return 1
    fi

    log_info "Processing: $template_file -> $output_file"

    # Read template
    local content
    content=$(<"$template_file")

    # Replace placeholders
    content="${content//\$\{GIT_NAME_PERSONAL\}/${GIT_NAME_PERSONAL:-}}"
    content="${content//\$\{GIT_EMAIL_PERSONAL\}/${GIT_EMAIL_PERSONAL:-}}"
    content="${content//\$\{GIT_NAME_WORK\}/${GIT_NAME_WORK:-}}"
    content="${content//\$\{GIT_EMAIL_WORK\}/${GIT_EMAIL_WORK:-}}"
    content="${content//\$\{GIT_SIGNING_KEY\}/${GIT_SIGNING_KEY:-}}"
    content="${content//\$\{WORK_SIGNING_KEY\}/${WORK_SIGNING_KEY:-}}"
    content="${content//\$\{WORK_GPG_SECTION\}/${WORK_GPG_SECTION:-}}"
    content="${content//\$\{WORK_REPO_DIR\}/${WORK_REPO_DIR:-}}"
    content="${content//\$\{OP_SSH_SIGN_PATH\}/${OP_SSH_SIGN_PATH:-}}"
    content="${content//\$\{GIT_COMMIT_GPGSIGN\}/${GIT_COMMIT_GPGSIGN:-false}}"
    content="${content//\$\{GIT_CREDENTIAL_HELPER\}/${GIT_CREDENTIAL_HELPER:-store}}"
    content="${content//\$\{DATA_DIR\}/${DATA_DIR:-}}"
    content="${content//\$\{HOME\}/$HOME}"

    # An includeIf with an empty gitdir pattern (no work folder given) matches
    # every repository, so the included identity would apply everywhere. Leave
    # the block out: its header, its lines, and the blank line after it.
    if [[ "$content" == *'[includeIf "gitdir:"]'* ]]; then
        content="$(printf '%s\n' "$content" | awk '
            $0 == "[includeIf \"gitdir:\"]" { skip = 1; next }
            skip && /^\[/ { skip = 0 }
            skip && /^[[:space:]]*$/ { skip = 0; next }
            !skip { print }')"
        log_info "No work repository folder: the work includeIf is left out"
    fi

    # Create output directory if needed
    mkdir -p "$(dirname "$output_file")"

    # Backup existing file before overwriting
    if [[ -f "$output_file" ]] && [[ ! -L "$output_file" ]]; then
        local backup_dir
        backup_dir="${HOME}/.dotfiles-backup/$(date +%Y%m%d%H%M%S)"
        mkdir -p "$backup_dir"
        local backup_name
        backup_name=$(basename "$output_file")
        cp "$output_file" "${backup_dir}/${backup_name}"
        log_info "Backed up: ${output_file} -> ${backup_dir}/${backup_name}"
    fi

    # Write output file
    printf '%s\n' "$content" > "$output_file"

    log_info "Created: $output_file"
}

# --- Work profile git config ---------------------------------------------
#
# The work file is the personal template less what a company Mac decides for
# itself or ns-bootstrap sets per mode: identity and signing ([user], [gpg],
# commit and tag gpgsign), the credential helper, the global hooks path, and
# the includeIf that splits personal from work. Built from the template, not
# copied, so the shared settings cannot drift apart. Section-header comments
# are dropped, as they would label sections that are gone.
work_gitconfig_body() {    # TEMPLATE
    awk '
        /^\[/ { sec = $0; drop = (sec ~ /^\[(user|credential|gpg)( |\])/ || sec ~ /^\[includeIf /) }
        drop { next }
        /^# ─── / { next }
        sec == "[core]" && $1 == "hooksPath" { next }
        (sec == "[commit]" || sec == "[tag]") && $1 == "gpgsign" { next }
        { print }' "$1" | cat -s
}

_git_quote() {             # VALUE: a double-quoted git config value
    local v="${1//\\/\\\\}"
    printf '"%s"' "${v//\"/\\\"}"
}

# Prints the whole work file. Uses GIT_NAME_WORK, GIT_EMAIL_WORK,
# WORK_SIGNING (none, ssh-file, 1password or gpg), WORK_SIGNING_KEY and, for
# 1password, OP_SSH_SIGN_PATH.
work_gitconfig() {         # TEMPLATE
    local body
    printf '%s\n' "# ns-bootstrap work git settings, included from ~/.config/git/config." \
        "# Written by secrets/work-secrets.sh; run it again to change them." \
        "# ~/.gitconfig is read after this file, so anything it sets wins." ""
    printf '[user]\n    name = %s\n    email = %s\n' "$(_git_quote "$GIT_NAME_WORK")" "$(_git_quote "$GIT_EMAIL_WORK")"
    if [[ "${WORK_SIGNING:-none}" != none ]]; then
        printf '    signingkey = %s\n\n' "$(_git_quote "$WORK_SIGNING_KEY")"
        case "$WORK_SIGNING" in
            gpg) printf '[gpg]\n    format = openpgp\n\n' ;;
            *)   printf '[gpg]\n    format = ssh\n\n' ;;
        esac
        [[ "$WORK_SIGNING" == 1password ]] && printf '[gpg "ssh"]\n    program = %s\n\n' "$(_git_quote "$OP_SSH_SIGN_PATH")"
        printf '[commit]\n    gpgsign = true\n\n[tag]\n    gpgsign = true\n'
    fi
    body="$(work_gitconfig_body "$1")"
    printf '\n%s\n' "${body//\$\{HOME\}/$HOME}"
}
