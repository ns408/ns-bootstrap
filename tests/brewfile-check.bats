#!/usr/bin/env bats
# Tests for scripts/check-brewfile.sh, with a stand-in `brew` serving canned
# `brew info --json=v2` answers, so each kind of finding can be exercised
# without the network: not found, disabled, deprecated and renamed.

CHECK="${BATS_TEST_DIRNAME}/../scripts/check-brewfile.sh"

setup() {
    TEST_DIR=$(mktemp -d)
    STUB="${TEST_DIR}/stub"
    mkdir -p "${STUB}/bin" "${STUB}/formula" "${STUB}/cask"
    export STUB

    # brew stand-in: `brew info --json=v2 --formula|--cask NAME` prints the
    # canned answer for NAME, or fails as brew does for an unknown name.
    # Every call is logged, so tests can see what was looked up and how.
    cat > "${STUB}/bin/brew" <<'BREW'
#!/usr/bin/env bash
echo "$*" >> "${STUB}/calls"
[[ "$1 $2" == "info --json=v2" ]] || exit 99
kind=${3#--} name=$4
f="${STUB}/${kind}/${name//\//_}.json"
[[ -f "$f" ]] || { echo "Error: No available ${kind} with the name \"${name}\"." >&2; exit 1; }
cat "$f"
BREW
    chmod +x "${STUB}/bin/brew"
    export PATH="${STUB}/bin:${PATH}"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# formula NAME [JSON-FIELDS]: brew's answer for a formula looked up as NAME
formula() {
    echo "{\"formulae\": [{\"name\": \"${1##*/}\", \"oldnames\": [], \"aliases\": []${2:+, $2}}], \"casks\": []}" \
        > "${STUB}/formula/${1//\//_}.json"
}

# cask NAME [JSON-FIELDS]: brew's answer for a cask looked up as NAME
cask() {
    echo "{\"formulae\": [], \"casks\": [{\"token\": \"$1\", \"old_tokens\": []${2:+, $2}}]}" \
        > "${STUB}/cask/$1.json"
}

brewfile() {  # NAME, then the file's lines on stdin
    cat > "${TEST_DIR}/$1"
    echo "${TEST_DIR}/$1"
}

@test "current formulae and casks pass" {
    formula jq
    cask firefox
    f=$(brewfile Brewfile <<'EOF'
brew "jq"
cask "firefox"
EOF
)
    run "$CHECK" "$f"
    [[ "$status" -eq 0 ]] || { echo "$output"; false; }
    [[ "$output" == *'ok  brew "jq"'* ]]
    [[ "$output" == *'ok  cask "firefox"'* ]]
    [[ "$output" != *'::error'* ]]
}

@test "a disabled formula fails and names its replacement" {
    formula tldr '"deprecated": true, "deprecation_date": "2024-10-24", "deprecation_reason": "unmaintained", "deprecation_replacement_formula": "tlrc", "disabled": true, "disable_date": "2025-10-24", "disable_reason": "unmaintained"'
    f=$(brewfile Brewfile <<< 'brew "tldr"')
    run "$CHECK" "$f"
    [[ "$status" -eq 1 ]] || { echo "$output"; false; }
    [[ "$output" == *"::error file=${f}::brew \"tldr\": disabled since 2025-10-24 (unmaintained); replace it with tlrc"* ]] \
        || { echo "$output"; false; }
}

@test "a disabled formula with no replacement says to remove it" {
    formula gone '"disabled": true, "disable_date": "2025-01-01", "disable_reason": "does_not_build"'
    f=$(brewfile Brewfile <<< 'brew "gone"')
    run "$CHECK" "$f"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'brew "gone": disabled since 2025-01-01 (does_not_build); remove it'* ]] \
        || { echo "$output"; false; }
}

@test "a deprecated formula fails, a year before it is disabled" {
    formula old '"deprecated": true, "deprecation_date": "2026-09-01", "deprecation_reason": "repo_archived", "deprecation_replacement_formula": "new", "disabled": false'
    f=$(brewfile Brewfile <<< 'brew "old"')
    run "$CHECK" "$f"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'brew "old": deprecated since 2026-09-01 (repo_archived), to be disabled; replace it with new'* ]] \
        || { echo "$output"; false; }
}

@test "a deprecated cask names a replacement cask" {
    cask oldapp '"deprecated": true, "deprecation_date": "2026-08-01", "deprecation_reason": "discontinued", "deprecation_replacement_cask": "newapp", "disabled": false'
    f=$(brewfile Brewfile <<< 'cask "oldapp"')
    run "$CHECK" "$f"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'cask "oldapp": deprecated since 2026-08-01 (discontinued), to be disabled; replace it with newapp'* ]] \
        || { echo "$output"; false; }
}

@test "an entry Homebrew does not know fails" {
    f=$(brewfile Brewfile <<< 'brew "nosuchthing"')
    run "$CHECK" "$f"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'brew "nosuchthing": not found in Homebrew'* ]] || { echo "$output"; false; }
}

@test "a not-found finding quotes brew's own reason" {
    # brew says why on stderr, for example that a formula moved to a cask
    cat > "${STUB}/bin/brew" <<'BREW'
#!/usr/bin/env bash
echo "Warning: an unrelated warning" >&2
echo 'Error: No available formula with the name "azure-cli". It was migrated to homebrew/cask.' >&2
echo "  a detail on a second line" >&2
exit 1
BREW
    f=$(brewfile Brewfile <<< 'brew "azure-cli"')
    run "$CHECK" "$f"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'brew "azure-cli": not found in Homebrew (brew: No available formula with the name "azure-cli". It was migrated to homebrew/cask.); remove it or list what replaced it'* ]] \
        || { echo "$output"; false; }
}

@test "a renamed cask fails and names the new token" {
    # brew resolves the old token to the renamed cask
    echo '{"formulae": [], "casks": [{"token": "docker-desktop", "old_tokens": ["docker"]}]}' \
        > "${STUB}/cask/docker.json"
    f=$(brewfile Brewfile <<< 'cask "docker"')
    run "$CHECK" "$f"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'cask "docker": renamed to docker-desktop; use the new name'* ]] \
        || { echo "$output"; false; }
}

@test "a renamed formula fails and names the new name" {
    echo '{"formulae": [{"name": "newname", "oldnames": ["oldname"], "aliases": []}], "casks": []}' \
        > "${STUB}/formula/oldname.json"
    f=$(brewfile Brewfile <<< 'brew "oldname"')
    run "$CHECK" "$f"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'brew "oldname": renamed to newname; use the new name'* ]] || { echo "$output"; false; }
}

@test "a formula listed by an alias passes" {
    echo '{"formulae": [{"name": "postgresql@17", "oldnames": [], "aliases": ["postgresql"]}], "casks": []}' \
        > "${STUB}/formula/postgresql.json"
    f=$(brewfile Brewfile <<< 'brew "postgresql"')
    run "$CHECK" "$f"
    [[ "$status" -eq 0 ]] || { echo "$output"; false; }
}

@test "casks are looked up as casks, not as the formula of the same name" {
    formula docker
    echo '{"formulae": [], "casks": [{"token": "docker-desktop", "old_tokens": ["docker"]}]}' \
        > "${STUB}/cask/docker.json"
    f=$(brewfile Brewfile <<< 'cask "docker"')
    run "$CHECK" "$f"
    [[ "$status" -eq 1 ]]
    grep -qx 'info --json=v2 --cask docker' "${STUB}/calls"
}

@test "tap formulae and entries with options parse" {
    formula hashicorp/tap/terraform
    formula ffmpeg
    f=$(brewfile Brewfile <<'EOF'
brew "hashicorp/tap/terraform"
brew "ffmpeg", args: ["with-fdk-aac"]
EOF
)
    run "$CHECK" "$f"
    [[ "$status" -eq 0 ]] || { echo "$output"; false; }
    grep -qx 'info --json=v2 --formula hashicorp/tap/terraform' "${STUB}/calls"
    grep -qx 'info --json=v2 --formula ffmpeg' "${STUB}/calls"
}

@test "taps, App Store apps, comments and blank lines are skipped" {
    formula jq
    f=$(brewfile Brewfile <<'EOF'
# Tools
tap "hashicorp/tap"

mas "Xcode", id: 497799835
brew "jq"  # JSON
EOF
)
    run "$CHECK" "$f"
    [[ "$status" -eq 0 ]] || { echo "$output"; false; }
    [[ "$(cat "${STUB}/calls")" == 'info --json=v2 --formula jq' ]] || { cat "${STUB}/calls"; false; }
}

@test "several Brewfiles in one run report each file's findings" {
    formula jq
    a=$(brewfile Brewfile.a <<< 'brew "missing-a"')
    b=$(brewfile Brewfile.b <<'EOF'
brew "jq"
cask "missing-b"
EOF
)
    run "$CHECK" "$a" "$b"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"::error file=${a}::brew \"missing-a\""* ]] || { echo "$output"; false; }
    [[ "$output" == *"::error file=${b}::cask \"missing-b\""* ]] || { echo "$output"; false; }
    [[ "$output" == *'ok  brew "jq"'* ]]
    [[ "$output" == *'2 entries need a Brewfile edit'* ]] || { echo "$output"; false; }
}

@test "no Brewfile, or one that cannot be read, is a usage error" {
    run "$CHECK"
    [[ "$status" -eq 2 ]]
    run "$CHECK" "${TEST_DIR}/absent"
    [[ "$status" -eq 2 ]]
}
