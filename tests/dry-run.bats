#!/usr/bin/env bats
# bootstrap.sh --dry-run output, pinned by a golden so a change to what the
# preview promises is deliberate. ANSI colours are stripped, the repo path
# becomes @ROOT@ and the Brewfile's package count becomes N.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
}

@test "minimal dry run on macOS matches its golden" {
    [[ "$OSTYPE" == darwin* ]] || skip "golden is for macOS"
    run bash -c '"$1/install/bootstrap.sh" --profile minimal --dry-run < /dev/null 2>&1' _ "$ROOT"
    [[ "$status" -eq 0 ]]
    actual=$(printf '%s\n' "$output" \
        | sed -E $'s/\x1b\\[[0-9;]*m//g' \
        | sed -e "s|${ROOT}|@ROOT@|g" -E -e 's/\([0-9]+ packages\)/(N packages)/')
    diff "${BATS_TEST_DIRNAME}/fixtures/dry-run.minimal.macos.golden" <(printf '%s\n' "$actual")
}
