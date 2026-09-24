#!/usr/bin/env bats
# Tests for scripts/bump-git-pins.sh, with a stand-in `gh` serving canned API
# responses, so the rules that matter can be exercised: force-pushed branches,
# rewritten history and hand-made bumps.

BUMP="${BATS_TEST_DIRNAME}/../scripts/bump-git-pins.sh"

P=1111111111111111111111111111111111111111   # current pin
A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa   # pushed 30 days ago
B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb   # pushed 20 days ago
C=cccccccccccccccccccccccccccccccccccccccc   # pushed 2 days ago

setup() {
    TEST_DIR=$(mktemp -d)
    STUB="${TEST_DIR}/stub"
    mkdir -p "${STUB}/bin" "${STUB}/compare"
    export STUB
    export GIT_PINS_FILE="${TEST_DIR}/pins"
    REPORT="${TEST_DIR}/report.md"

    # gh stand-in: map the API path to a canned JSON file, then apply --jq.
    cat > "${STUB}/bin/gh" <<'GH'
#!/usr/bin/env bash
path="" expr="."
while [[ $# -gt 0 ]]; do
    case "$1" in
        --jq) expr="$2"; shift ;;
        repos/*) path="${1%%\?*}" ;;
    esac
    shift
done
case "$path" in
    */activity)   json="${STUB}/activity.json" ;;
    */compare/*)  json="${STUB}/compare/${path##*/compare/}.json" ;;
    repos/*)      json="${STUB}/repo.json" ;;
esac
jq -rc "$expr" "$json"
GH
    chmod +x "${STUB}/bin/gh"
    export PATH="${STUB}/bin:${PATH}"
    echo '{"default_branch": "main"}' > "${STUB}/repo.json"

    echo "zsh-plugin plug owner/plug ${P}" > "$GIT_PINS_FILE"
}

teardown() {
    rm -rf "$TEST_DIR"
}

days_ago() {
    jq -nr --argjson d "$1" 'now - $d * 86400 | todate'
}

# activity <type:days_ago:sha>...: the branch's push record.
activity() {
    local entries=() type days sha
    for spec in "$@"; do
        IFS=: read -r type days sha <<< "$spec"
        entries+=("{\"ref\":\"refs/heads/main\",\"activity_type\":\"${type}\",\"timestamp\":\"$(days_ago "$days")\",\"after\":\"${sha}\"}")
    done
    local IFS=,
    echo "[${entries[*]}]" > "${STUB}/activity.json"
}

# compare <base> <head> <status> [total]: canned compare API answer.
compare() {
    echo "{\"status\":\"$3\",\"total_commits\":${4:-0}}" > "${STUB}/compare/$1...$2.json"
}

pinned() {
    awk '{print $4}' "$GIT_PINS_FILE"
}

@test "moves to where the branch stood 14 days ago, ignoring newer pushes" {
    activity push:30:$A push:20:$B push:2:$C
    compare $B main ahead 1
    compare $P $B ahead 7

    run "$BUMP" --report "$REPORT"

    [[ "$status" -eq 0 ]]
    [[ "$(pinned)" == "$B" ]]
    grep -q "owner/plug.*| 7 |" "$REPORT"
    grep -q "compare/${P}...${B}" "$REPORT"
}

@test "a branch force-pushed in the last 90 days is held back for review" {
    activity push:30:$A force_push:25:$B push:2:$C
    compare $B main ahead 1
    compare $P $B ahead 7

    run "$BUMP" --report "$REPORT"

    [[ "$(pinned)" == "$P" ]]
    grep -q "force-pushed" "$REPORT"
}

@test "a candidate rewritten off the branch is held back" {
    activity push:30:$A push:20:$B
    compare $B main diverged

    run "$BUMP" --report "$REPORT"

    [[ "$(pinned)" == "$P" ]]
    grep -q "no longer on" "$REPORT"
}

@test "a pin that no longer lines up with upstream history is held back" {
    activity push:20:$B
    compare $B main identical
    compare $P $B diverged

    run "$BUMP" --report "$REPORT"

    [[ "$(pinned)" == "$P" ]]
    grep -q "have diverged" "$REPORT"
}

@test "a pin bumped ahead by hand is kept, not moved back" {
    activity push:20:$B push:2:$C
    compare $B main ahead 1
    compare $P $B behind

    run "$BUMP" --report "$REPORT"

    [[ "$(pinned)" == "$P" ]]
    grep -q "No pins to move" "$REPORT"
    [[ "$(grep -c "Held back" "$REPORT")" -eq 0 ]]
}

@test "nothing pushed long enough ago means no move" {
    activity push:3:$C

    run "$BUMP" --report "$REPORT"

    [[ "$(pinned)" == "$P" ]]
    grep -q "No push old enough" "$REPORT"
}

@test "an unset pin takes the candidate as its first pin" {
    echo "zsh-plugin plug owner/plug 0000000000000000000000000000000000000000" > "$GIT_PINS_FILE"
    activity push:20:$B push:2:$C
    compare $B main ahead 1

    run "$BUMP" --report "$REPORT"

    [[ "$(pinned)" == "$B" ]]
    grep -q "first pin" "$REPORT"
}
