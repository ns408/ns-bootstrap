#!/usr/bin/env bats
# Tests for process_template (install/lib/template.sh)
#
# The goldens in tests/fixtures/ were rendered by the function as it stood in
# secrets/bootstrap-secrets.sh before it moved, with the inputs below. A change
# to either template, or to the function, must update them on purpose.

setup() {
    TEST_DIR=$(mktemp -d)
    ROOT="${BATS_TEST_DIRNAME}/.."
    FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
    source "${ROOT}/install/lib/common.sh"
    source "${ROOT}/install/lib/template.sh"

    HOME=/home/example
    GIT_NAME_PERSONAL="Example Person"
    GIT_EMAIL_PERSONAL="person@example.com"
    GIT_NAME_WORK="Example Person"
    GIT_EMAIL_WORK="person@work.example.com"
    GIT_SIGNING_KEY="ssh-ed25519 AAAAexamplepersonalkey"
    WORK_SIGNING_KEY="ssh-ed25519 AAAAexampleworkkey"
    WORK_GPG_SECTION=""
    # shellcheck disable=SC2088  # a literal ~ is what git includeIf expects
    WORK_REPO_DIR="~/work/"
    OP_SSH_SIGN_PATH="/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
    GIT_COMMIT_GPGSIGN="true"
    GIT_CREDENTIAL_HELPER="osxkeychain"
    DATA_DIR="/home/example/data"
}

teardown() {
    [[ -n "${GNUPGHOME:-}" ]] && gpgconf --kill gpg-agent 2>/dev/null
    rm -rf "$TEST_DIR"
}

ssh_key() {                # NAME: a throwaway key pair at $TEST_DIR/keys/NAME, no passphrase
    mkdir -p "${TEST_DIR}/keys"
    ssh-keygen -q -t ed25519 -N "" -C "$1" -f "${TEST_DIR}/keys/$1"
}

fingerprint() {            # NAME
    ssh-keygen -lf "${TEST_DIR}/keys/$1.pub" | awk '{ print $2 }'
}

gpg_key() {                # EMAIL: a throwaway signing key; sets GPG_ID, or skips the test
    command -v gpg >/dev/null || skip "gpg not installed"
    export GNUPGHOME="${TEST_DIR}/gnupg"
    mkdir -m 700 "$GNUPGHOME"
    gpg --batch --quiet --passphrase '' --quick-gen-key "Example Person <$1>" ed25519 sign never 2>/dev/null \
        || skip "gpg cannot make a key here"
    GPG_ID="$(gpg --batch --list-secret-keys --with-colons | awk -F: '$1 == "sec" { print $5; exit }')"
}

signed_commit() {          # DIR FORMAT: an empty commit in a new repository at DIR, then FORMAT of it
    git init -q "$1"
    git_in "$1" commit -q --allow-empty -m test
    git_in "$1" log -1 --format="$2"
}

# A plain "! cmd" line never fails a bats test (set -e ignores it).
refute_grep() {
    if grep -q "$@"; then
        echo "unexpected match: $*"
        return 1
    fi
}

render_home() {            # both templates into a throwaway HOME, as bootstrap-secrets.sh does
    HOME="$TEST_DIR"
    process_template "${ROOT}/dotfiles/git/.gitconfig.template" "${HOME}/.gitconfig"
    process_template "${ROOT}/dotfiles/git/.gitconfig-work.template" "${HOME}/.gitconfig-work"
}

git_in() {                 # DIR ARGS: git in DIR as that HOME sees it, with a clean environment
    local dir="$1"
    shift
    env -i HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" PATH="$PATH" GIT_CONFIG_NOSYSTEM=1 \
        ${GNUPGHOME:+"GNUPGHOME=$GNUPGHOME"} git -C "$dir" "$@"
}

@test "personal gitconfig renders exactly as before" {
    process_template "${ROOT}/dotfiles/git/.gitconfig.template" "${TEST_DIR}/gitconfig"
    diff "${FIXTURES}/gitconfig.personal.golden" "${TEST_DIR}/gitconfig"
}

@test "work gitconfig renders exactly as before" {
    process_template "${ROOT}/dotfiles/git/.gitconfig-work.template" "${TEST_DIR}/gitconfig-work"
    diff "${FIXTURES}/gitconfig-work.golden" "${TEST_DIR}/gitconfig-work"
}

# git applies an includeIf with an empty gitdir pattern to every repository.
@test "with no work folder the work include is left out and the personal identity applies" {
    unset WORK_REPO_DIR
    render_home
    refute_grep -F 'gitdir:"' "${HOME}/.gitconfig"
    git init -q "${TEST_DIR}/repo"
    [[ "$(git_in "${TEST_DIR}/repo" config --show-origin user.email)" == "file:${HOME}/.gitconfig"$'\t'"person@example.com" ]]
}

@test "with a work folder only repositories inside it get the work identity" {
    render_home             # WORK_REPO_DIR is ~/work/, as people enter it
    git init -q "${TEST_DIR}/work/repo"
    git init -q "${TEST_DIR}/personal"
    [[ "$(git_in "${TEST_DIR}/work/repo" config user.email)" == person@work.example.com ]]
    [[ "$(git_in "${TEST_DIR}/personal" config user.email)" == person@example.com ]]
}

# ssh-keygen stands in for op-ssh-sign: git calls both the same way.
@test "SSH signing: personal and work repositories each sign with their own key" {
    ssh_key personal
    ssh_key work
    GIT_SIGNING_KEY="${TEST_DIR}/keys/personal.pub" WORK_SIGNING_KEY="${TEST_DIR}/keys/work.pub"
    OP_SSH_SIGN_PATH="$(command -v ssh-keygen)"
    render_home
    printf '%s %s\n' person@example.com "$(cat "${TEST_DIR}/keys/personal.pub")" \
        person@work.example.com "$(cat "${TEST_DIR}/keys/work.pub")" > "${HOME}/.gitconfig_allowed-signers"
    [[ "$(signed_commit "${TEST_DIR}/personal" '%G? %GF %ae')" == "G $(fingerprint personal) person@example.com" ]]
    [[ "$(signed_commit "${TEST_DIR}/work/repo" '%G? %GF %ae')" == "G $(fingerprint work) person@work.example.com" ]]
}

@test "GPG signing: a work key signs with openpgp while personal repositories keep SSH" {
    gpg_key person@work.example.com
    ssh_key personal
    GIT_SIGNING_KEY="${TEST_DIR}/keys/personal.pub" OP_SSH_SIGN_PATH="$(command -v ssh-keygen)"
    # What bootstrap-secrets.sh sets when work uses GPG.
    WORK_SIGNING_KEY="$GPG_ID" WORK_GPG_SECTION=$'[gpg]\n    format = openpgp'
    render_home
    printf '%s %s\n' person@example.com "$(cat "${TEST_DIR}/keys/personal.pub")" > "${HOME}/.gitconfig_allowed-signers"
    [[ "$(signed_commit "${TEST_DIR}/work/repo" '%G? %GK')" == "G $GPG_ID" ]]
    [[ "$(signed_commit "${TEST_DIR}/personal" '%G? %GF')" == "G $(fingerprint personal)" ]]
}

@test "unset signing and credential values fall back to false and store" {
    unset GIT_COMMIT_GPGSIGN GIT_CREDENTIAL_HELPER
    process_template "${ROOT}/dotfiles/git/.gitconfig.template" "${TEST_DIR}/gitconfig"
    [[ "$(grep -c '^    gpgsign = false$' "${TEST_DIR}/gitconfig")" -eq 2 ]]
    grep -qx '    helper = store' "${TEST_DIR}/gitconfig"
}

@test "an existing output file is backed up before it is replaced" {
    HOME="$TEST_DIR"
    echo "old content" > "${TEST_DIR}/gitconfig"
    process_template "${ROOT}/dotfiles/git/.gitconfig-work.template" "${TEST_DIR}/gitconfig"
    grep -qx "old content" "${TEST_DIR}"/.dotfiles-backup/*/gitconfig
    grep -qx "    email = person@work.example.com" "${TEST_DIR}/gitconfig"
}

@test "the work body is the personal template less identity, signing, credentials, hooks path and includeIf" {
    body="$(work_gitconfig_body "${ROOT}/dotfiles/git/.gitconfig.template")"
    [[ "$body" != *"[user]"* && "$body" != *"[credential]"* && "$body" != *"[includeIf"* ]]
    [[ "$body" != *"[gpg"* && "$body" != *hooksPath* && "$body" != *gpgsign* ]]
    # Everything else is carried over: each remaining key line appears in the template.
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* || "$line" == \[* ]] && continue
        grep -qxF -- "$line" "${ROOT}/dotfiles/git/.gitconfig.template" || { echo "not from the template: $line"; false; }
    done <<< "$body"
    [[ "$body" == *"[alias]"* && "$body" == *"defaultBranch = main"* ]]
}

@test "the work file quotes values so git reads them back exactly" {
    GIT_NAME_WORK='Example "Q" Person; #1 \ x' GIT_EMAIL_WORK=person@work.example.com WORK_SIGNING=none
    work_gitconfig "${ROOT}/dotfiles/git/.gitconfig.template" > "${TEST_DIR}/work"
    [[ "$(git config --file "${TEST_DIR}/work" user.name)" == "$GIT_NAME_WORK" ]]
    [[ "$(grep -c '\${' "${TEST_DIR}/work")" == 0 ]]
}

@test "a missing template returns 1 and writes nothing" {
    run process_template "${TEST_DIR}/no-such.template" "${TEST_DIR}/out"
    [[ "$status" -eq 1 ]]
    [[ ! -e "${TEST_DIR}/out" ]]
}
