#!/usr/bin/env bats
# secrets/work-secrets.sh: the work git identity in its own file, included
# from ~/.config/git/config, with ~/.gitconfig left alone. Runs with a
# throwaway HOME, no terminal, and an op stub that logs every call.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    TEST_HOME=$(mktemp -d)
    STUBS="${TEST_HOME}/stubs"
    mkdir -p "$STUBS"
    export STUB_LOG="${TEST_HOME}/stub.log"
    WORK_FILE="${TEST_HOME}/.config/ns-bootstrap/gitconfig"
}

teardown() {
    [[ -n "${GNUPGHOME:-}" ]] && gpgconf --kill gpg-agent 2>/dev/null
    rm -rf "$TEST_HOME"
}

signed_commit() {          # FORMAT [ALLOWED_SIGNERS]: an empty commit in a new repository, then FORMAT of it
    local repo="${TEST_HOME}/repo"
    git init -q "$repo"
    env -i HOME="$TEST_HOME" TMPDIR="${TMPDIR:-/tmp}" PATH="$PATH" GIT_CONFIG_NOSYSTEM=1 \
        ${GNUPGHOME:+"GNUPGHOME=$GNUPGHOME"} git -C "$repo" commit -q --allow-empty -m test
    env -i HOME="$TEST_HOME" TMPDIR="${TMPDIR:-/tmp}" PATH="$PATH" GIT_CONFIG_NOSYSTEM=1 \
        ${GNUPGHOME:+"GNUPGHOME=$GNUPGHOME"} git -C "$repo" ${2:+-c "gpg.ssh.allowedSignersFile=$2"} \
        log -1 --format="$1"
}

# A plain "! cmd" line never fails a bats test (set -e ignores it).
refute_grep() {
    if grep -q "$@"; then
        echo "unexpected match: $*"
        return 1
    fi
}

op_stub() {                # EXIT: an op that logs its arguments and exits EXIT
    printf '#!/usr/bin/env bash\necho "op[${OP_ACCOUNT:-}] $*" >> "$STUB_LOG"\nexit %s\n' "$1" > "${STUBS}/op"
    chmod 755 "${STUBS}/op"
}

secrets() {                # extra environment, then the script runs with --yes
    run env -i HOME="$TEST_HOME" PATH="${STUBS}:/usr/bin:/bin" STUB_LOG="$STUB_LOG" GIT_CONFIG_NOSYSTEM=1 \
        NS_BOOTSTRAP_GIT_NAME="Example Person" NS_BOOTSTRAP_GIT_EMAIL="person@work.example.com" \
        "$@" bash "${ROOT}/secrets/work-secrets.sh" --yes < /dev/null
}

lookup() {                 # KEY: what git resolves for this HOME, with a clean environment
    (cd "$TEST_HOME" && env -i HOME="$TEST_HOME" PATH="/usr/bin:/bin" GIT_CONFIG_NOSYSTEM=1 git config --get "$1")
}

@test "the work identity lands in its own file, included from ~/.config/git/config" {
    secrets
    [[ "$status" -eq 0 ]]
    [[ "$(git config --file "$WORK_FILE" user.email)" == person@work.example.com ]]
    # shellcheck disable=SC2088  # the literal ~ is what the include holds
    [[ "$(git config --file "${TEST_HOME}/.config/git/config" --get-all include.path)" == "~/.config/ns-bootstrap/gitconfig" ]]
    [[ "$(lookup user.email)" == person@work.example.com ]]
    [[ ! -e "${TEST_HOME}/.gitconfig" ]]
}

@test "a ~/.gitconfig already there is untouched and wins" {
    printf '[user]\n\temail = it@company.example.com\n[credential]\n\thelper = company-helper\n' > "${TEST_HOME}/.gitconfig"
    before="$(cat "${TEST_HOME}/.gitconfig")"
    secrets
    [[ "$status" -eq 0 ]]
    [[ "$(cat "${TEST_HOME}/.gitconfig")" == "$before" ]]
    [[ "$(lookup user.email)" == it@company.example.com ]]
    [[ "$(lookup credential.helper)" == company-helper ]]
    [[ "$output" == *"sets user.email itself, so it wins"* ]]
}

@test "the work file sets no credential helper, hooks path, includeIf or personal identity" {
    secrets
    [[ "$status" -eq 0 ]]
    run git config --file "$WORK_FILE" --list
    [[ "$output" != *credential.* && "$output" != *core.hookspath* && "$output" != *includeif.* ]]
    [[ "$output" != *gpgsign* && "$output" != *gpg.* && "$output" != *"\${"* ]]
    [[ "$output" == *"init.defaultbranch=main"* && "$output" == *"pull.rebase=true"* ]]
}

@test "a second run changes nothing and includes once" {
    secrets
    before="$(cat "$WORK_FILE")"
    secrets
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Up to date"* && "$output" == *"Already included"* ]]
    [[ "$(cat "$WORK_FILE")" == "$before" ]]
    [[ "$(git config --file "${TEST_HOME}/.config/git/config" --get-all include.path | wc -l | tr -d ' ')" == 1 ]]
}

@test "a later run without the settings keeps the identity it wrote" {
    secrets
    run env -i HOME="$TEST_HOME" PATH="/usr/bin:/bin" bash "${ROOT}/secrets/work-secrets.sh" --yes < /dev/null
    [[ "$status" -eq 0 ]]
    [[ "$(git config --file "$WORK_FILE" user.email)" == person@work.example.com ]]
}

@test "missing or bad values fail with status 2 and say which setting" {
    run env -i HOME="$TEST_HOME" PATH="/usr/bin:/bin" NS_BOOTSTRAP_GIT_NAME=x bash "${ROOT}/secrets/work-secrets.sh" --yes < /dev/null
    [[ "$status" -eq 2 && "$output" == *"set NS_BOOTSTRAP_GIT_EMAIL"* ]]
    secrets NS_BOOTSTRAP_GIT_EMAIL=not-an-address
    [[ "$status" -eq 2 && "$output" == *"does not look like an address"* ]]
    secrets NS_BOOTSTRAP_GIT_SIGNING=sometimes
    [[ "$status" -eq 2 && "$output" == *"must be none, ssh-file, 1password or gpg"* ]]
    [[ ! -e "$WORK_FILE" ]]
}

@test "ssh-file signing uses the key file" {
    mkdir -p "${TEST_HOME}/.ssh"
    echo "ssh-ed25519 AAAAexample" > "${TEST_HOME}/.ssh/id_ed25519.pub"
    secrets NS_BOOTSTRAP_GIT_SIGNING=ssh-file
    [[ "$status" -eq 0 ]]
    [[ "$(git config --file "$WORK_FILE" user.signingkey)" == "${TEST_HOME}/.ssh/id_ed25519.pub" ]]
    [[ "$(git config --file "$WORK_FILE" gpg.format)" == ssh ]]
    [[ "$(git config --file "$WORK_FILE" --get-all commit.gpgsign)" == true ]]
    secrets NS_BOOTSTRAP_GIT_SIGNING=ssh-file NS_BOOTSTRAP_GIT_SIGNING_KEY=~/missing
    [[ "$status" -eq 2 && "$output" == *"No SSH key file"* ]]
}

@test "gpg signing uses openpgp and a key ID" {
    secrets NS_BOOTSTRAP_GIT_SIGNING=gpg NS_BOOTSTRAP_GIT_SIGNING_KEY=0123456789ABCDEF  # gitleaks:allow (made-up test key ID)
    [[ "$status" -eq 0 ]]
    [[ "$(git config --file "$WORK_FILE" gpg.format)" == openpgp ]]
    [[ "$(git config --file "$WORK_FILE" user.signingkey)" == 0123456789ABCDEF ]]
}

@test "ssh-file signing signs a commit with the work key" {
    mkdir -p "${TEST_HOME}/.ssh"
    ssh-keygen -q -t ed25519 -N "" -C work -f "${TEST_HOME}/.ssh/id_ed25519"
    secrets NS_BOOTSTRAP_GIT_SIGNING=ssh-file
    [[ "$status" -eq 0 ]]
    echo "person@work.example.com $(cat "${TEST_HOME}/.ssh/id_ed25519.pub")" > "${TEST_HOME}/allowed"
    fp="$(ssh-keygen -lf "${TEST_HOME}/.ssh/id_ed25519.pub" | awk '{ print $2 }')"
    [[ "$(signed_commit '%G? %GF %ae' "${TEST_HOME}/allowed")" == "G $fp person@work.example.com" ]]
}

@test "gpg signing signs a commit with the work key" {
    command -v gpg >/dev/null || skip "gpg not installed"
    export GNUPGHOME="${TEST_HOME}/gnupg"
    mkdir -m 700 "$GNUPGHOME"
    gpg --batch --quiet --passphrase '' --quick-gen-key "Example Person <person@work.example.com>" ed25519 sign never \
        2>/dev/null || skip "gpg cannot make a key here"
    id="$(gpg --batch --list-secret-keys --with-colons | awk -F: '$1 == "sec" { print $5; exit }')"
    secrets NS_BOOTSTRAP_GIT_SIGNING=gpg NS_BOOTSTRAP_GIT_SIGNING_KEY="$id"
    [[ "$status" -eq 0 ]]
    [[ "$(signed_commit '%G? %GK %ae')" == "G $id person@work.example.com" ]]
}

@test "1password signing uses op-ssh-sign and the public key" {
    printf '#!/bin/sh\n' > "${STUBS}/op-ssh-sign"
    chmod 755 "${STUBS}/op-ssh-sign"
    secrets NS_BOOTSTRAP_GIT_SIGNING=1password NS_BOOTSTRAP_GIT_SIGNING_KEY="ssh-ed25519 AAAAexample" \
        OP_SSH_SIGN_PATH="${STUBS}/op-ssh-sign"
    [[ "$status" -eq 0 ]]
    [[ "$(git config --file "$WORK_FILE" gpg.ssh.program)" == "${STUBS}/op-ssh-sign" ]]
    [[ "$(git config --file "$WORK_FILE" user.signingkey)" == "ssh-ed25519 AAAAexample" ]]
}

@test "with no 1Password, op is never called" {
    op_stub 0
    secrets
    [[ "$status" -eq 0 ]]
    [[ ! -e "$STUB_LOG" ]]
}

@test "1Password asked for but failing does not stop the run" {
    op_stub 1
    secrets NS_BOOTSTRAP_SECRETS_PROVIDER=1password NS_BOOTSTRAP_OP_VAULT=Employee
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"not signed in"* && "$output" == *"continuing without 1Password"* ]]
    [[ -f "$WORK_FILE" ]]
}

@test "1Password, when it works, gets the work fields in the vault named" {
    op_stub 0
    secrets NS_BOOTSTRAP_SECRETS_PROVIDER=1password NS_BOOTSTRAP_OP_VAULT=Employee NS_BOOTSTRAP_OP_ACCOUNT=company
    [[ "$status" -eq 0 ]]
    grep -qE '^op\[company\] item (create|edit) .*--vault=Employee.*Git Work.email\[text\]=person@work.example.com' "$STUB_LOG"
    refute_grep 'Git Personal' "$STUB_LOG"
}

@test "bootstrap-secrets.sh hands a work Mac to work-secrets.sh" {
    mkdir -p "${TEST_HOME}/.config/ns-bootstrap"
    echo work > "${TEST_HOME}/.config/ns-bootstrap/profile"
    run env -i HOME="$TEST_HOME" PATH="${STUBS}:/usr/bin:/bin" GIT_CONFIG_NOSYSTEM=1 \
        NS_BOOTSTRAP_GIT_NAME="Example Person" NS_BOOTSTRAP_GIT_EMAIL="person@work.example.com" \
        bash "${ROOT}/secrets/bootstrap-secrets.sh" --yes < /dev/null
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Work git identity ready"* ]]
    [[ "$output" != *"Personal git"* && ! -e "${TEST_HOME}/.gitconfig" ]]
}
