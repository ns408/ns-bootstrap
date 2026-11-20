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
