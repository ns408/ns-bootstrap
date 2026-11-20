#!/usr/bin/env bats
# install/lib/settings.sh: where each setting comes from, the work defaults,
# and which values are refused.

setup() {
    TEST_HOME=$(mktemp -d)
    export HOME="$TEST_HOME"
    unset NS_BOOTSTRAP_SETTINGS_FILE NS_BOOTSTRAP_PROFILE_FILE
    unset NS_BOOTSTRAP_EXTRA_APPS NS_BOOTSTRAP_DAILY_UPDATE NS_BOOTSTRAP_DAILY_SCOPE \
          NS_BOOTSTRAP_BREWFILE_LOCAL HOMEBREW_NO_ANALYTICS
    mkdir -p "${HOME}/.config/ns-bootstrap"
    SETTINGS="${HOME}/.config/ns-bootstrap/settings"
    source "${BATS_TEST_DIRNAME}/../install/lib/settings.sh"
}

teardown() {
    rm -rf "$TEST_HOME"
}

@test "personal profiles default to today's behaviour" {
    for p in minimal developer cloud-engineer; do
        [[ "$(ns_setting NS_BOOTSTRAP_EXTRA_APPS "$p")" == on ]]
        [[ "$(ns_setting NS_BOOTSTRAP_DAILY_UPDATE "$p")" == on ]]
        [[ "$(ns_setting NS_BOOTSTRAP_DAILY_SCOPE "$p")" == all ]]
        [[ -z "$(ns_setting HOMEBREW_NO_ANALYTICS "$p")" ]]
        [[ -z "$(ns_setting NS_BOOTSTRAP_BREWFILE_LOCAL "$p")" ]]
    done
}

@test "the work profile defaults to no extra apps, no daily agent, formulae only, no analytics" {
    [[ "$(ns_setting NS_BOOTSTRAP_EXTRA_APPS work)" == off ]]
    [[ "$(ns_setting NS_BOOTSTRAP_DAILY_UPDATE work)" == off ]]
    [[ "$(ns_setting NS_BOOTSTRAP_DAILY_SCOPE work)" == formulae ]]
    [[ "$(ns_setting HOMEBREW_NO_ANALYTICS work)" == 1 ]]
}

@test "the settings file beats the default, and the environment beats both" {
    echo 'NS_BOOTSTRAP_DAILY_SCOPE=formulae' > "$SETTINGS"
    [[ "$(ns_setting NS_BOOTSTRAP_DAILY_SCOPE minimal)" == formulae ]]
    [[ "$(ns_setting_source NS_BOOTSTRAP_DAILY_SCOPE minimal)" == settings ]]
    NS_BOOTSTRAP_DAILY_SCOPE=all
    export NS_BOOTSTRAP_DAILY_SCOPE
    [[ "$(ns_setting NS_BOOTSTRAP_DAILY_SCOPE minimal)" == all ]]
    [[ "$(ns_setting_source NS_BOOTSTRAP_DAILY_SCOPE minimal)" == environment ]]
    [[ "$(ns_setting_source NS_BOOTSTRAP_DAILY_UPDATE minimal)" == default ]]
}

@test "the settings file is read, not run: quotes, comments and spacing" {
    cat > "$SETTINGS" <<'EOF'
# a comment
NS_BOOTSTRAP_DAILY_UPDATE = "off"   # trailing comment
NS_BOOTSTRAP_BREWFILE_LOCAL='~/company/Brewfile'
NS_BOOTSTRAP_EXTRA_APPS=$(touch "$HOME/ran")
EOF
    [[ "$(ns_setting NS_BOOTSTRAP_DAILY_UPDATE minimal)" == off ]]
    # shellcheck disable=SC2088  # the literal ~ is what the file holds
    [[ "$(ns_setting NS_BOOTSTRAP_BREWFILE_LOCAL minimal)" == "~/company/Brewfile" ]]
    [[ "$(ns_setting_path NS_BOOTSTRAP_BREWFILE_LOCAL minimal)" == "${HOME}/company/Brewfile" ]]
    [[ "$(ns_setting NS_BOOTSTRAP_EXTRA_APPS minimal)" == '$(touch "$HOME/ran")' ]]
    [[ ! -e "${HOME}/ran" ]]
}

@test "the last line for a setting wins" {
    printf 'NS_BOOTSTRAP_DAILY_SCOPE=all\nNS_BOOTSTRAP_DAILY_SCOPE=formulae\n' > "$SETTINGS"
    [[ "$(ns_setting NS_BOOTSTRAP_DAILY_SCOPE minimal)" == formulae ]]
}

@test "the remembered profile chooses the defaults when none is given" {
    [[ "$(ns_setting NS_BOOTSTRAP_DAILY_UPDATE)" == on ]]
    echo work > "${HOME}/.config/ns-bootstrap/profile"
    [[ "$(ns_remembered_profile)" == work ]]
    [[ "$(ns_setting NS_BOOTSTRAP_DAILY_UPDATE)" == off ]]
}

@test "valid settings pass the check" {
    printf 'NS_BOOTSTRAP_DAILY_UPDATE=on\nNS_BOOTSTRAP_DAILY_SCOPE=formulae\n' > "$SETTINGS"
    run ns_settings_check minimal
    [[ "$status" -eq 0 && -z "$output" ]]
    run ns_settings_check work
    [[ "$status" -eq 0 && -z "$output" ]]
}

@test "bad values are each named" {
    printf 'NS_BOOTSTRAP_DAILY_UPDATE=yes\nNS_BOOTSTRAP_DAILY_SCOPE=casks\nNS_BOOTSTRAP_BREWFILE_LOCAL=~/missing\n' > "$SETTINGS"
    run ns_settings_check minimal
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"NS_BOOTSTRAP_DAILY_UPDATE must be on or off, not 'yes'"* ]]
    [[ "$output" == *"NS_BOOTSTRAP_DAILY_SCOPE must be all or formulae, not 'casks'"* ]]
    [[ "$output" == *"NS_BOOTSTRAP_BREWFILE_LOCAL names no file: ${HOME}/missing"* ]]
}

@test "extra apps cannot be switched on for work" {
    echo 'NS_BOOTSTRAP_EXTRA_APPS=on' > "$SETTINGS"
    run ns_settings_check minimal
    [[ "$status" -eq 0 ]]
    run ns_settings_check work
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"cannot be on for the work profile"* ]]
}

@test "any HOMEBREW_NO_ANALYTICS value is accepted, as Homebrew does" {
    HOMEBREW_NO_ANALYTICS=true
    export HOMEBREW_NO_ANALYTICS
    run ns_settings_check minimal
    [[ "$status" -eq 0 ]]
}

@test "the helpers give the same answers under zsh" {
    command -v zsh >/dev/null || skip "zsh not installed"
    echo 'NS_BOOTSTRAP_DAILY_SCOPE=formulae' > "$SETTINGS"
    echo work > "${HOME}/.config/ns-bootstrap/profile"
    run zsh -c 'source "$1"; ns_setting NS_BOOTSTRAP_DAILY_SCOPE; ns_setting NS_BOOTSTRAP_DAILY_UPDATE; ns_settings_check work && echo valid' _ \
        "${BATS_TEST_DIRNAME}/../install/lib/settings.sh"
    [[ "$status" -eq 0 ]]
    [[ "$output" == $'formulae\noff\nvalid' ]]
}
