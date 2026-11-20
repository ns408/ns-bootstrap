#!/usr/bin/env bats
# bootstrap.sh command-line handling: a bad command line exits 2 before
# anything runs. Each case runs with a throwaway HOME, no --yes and stdin
# closed, so a regression stops at the first prompt instead of installing.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    TEST_HOME=$(mktemp -d)
}

teardown() {
    rm -rf "$TEST_HOME"
}

bootstrap() {
    run env -u NONINTERACTIVE HOME="$TEST_HOME" "${ROOT}/install/bootstrap.sh" "$@" < /dev/null
}

# The banner is the first thing a run prints; its absence shows nothing started.
refuses() {
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"$1"* ]]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" != *"ns-bootstrap - "* ]]
}

@test "a mistyped flag exits 2 before anything runs" {
    bootstrap --dryrun
    refuses "unknown option: --dryrun"
}

@test "a stray argument exits 2" {
    bootstrap minimal
    refuses "unknown option: minimal"
}

@test "an unknown option after valid ones still exits 2" {
    bootstrap --dry-run --profile minimal --verbose
    refuses "unknown option: --verbose"
}

@test "--profile with no name exits 2" {
    bootstrap --dry-run --profile
    refuses "--profile needs a name"
}

@test "--profile followed by another flag exits 2" {
    bootstrap --profile --dry-run
    refuses "--profile needs a name"
}

@test "an unknown profile exits 2" {
    bootstrap --dry-run --profile dev
    refuses "unknown profile: dev (choose minimal, developer, cloud-engineer)"
}

@test "--help prints usage and exits 0" {
    bootstrap --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"--profile NAME    Set profile: minimal, developer, cloud-engineer"* ]]
}

@test "each profile is accepted, in either flag order" {
    for p in minimal developer cloud-engineer; do
        bootstrap --profile "$p" --dry-run
        [[ "$status" -eq 0 ]]
        [[ "$output" == *"Profile:  ${p}"* ]]
        bootstrap -y --dry-run --profile "$p"
        [[ "$status" -eq 0 ]]
    done
}
