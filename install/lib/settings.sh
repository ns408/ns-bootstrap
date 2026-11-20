#!/usr/bin/env bash
# Settings for bootstrap.sh and the update functions. Sourced by bash and by
# zsh (update-system.sh), so it sticks to syntax both read the same way.
#
# A setting comes from, in order:
#   1. the environment (an exported, non-empty variable);
#   2. ~/.config/ns-bootstrap/settings, lines of KEY=value (quotes optional,
#      # starts a comment; the file is read, never sourced);
#   3. the default for the profile.
#
# The profile a Mac was set up with is remembered in
# ~/.config/ns-bootstrap/profile. Only the work profile is written there.

NS_BOOTSTRAP_SETTINGS_FILE="${NS_BOOTSTRAP_SETTINGS_FILE:-${HOME}/.config/ns-bootstrap/settings}"
NS_BOOTSTRAP_PROFILE_FILE="${NS_BOOTSTRAP_PROFILE_FILE:-${HOME}/.config/ns-bootstrap/profile}"

ns_remembered_profile() {
    local p=""
    [[ -f "$NS_BOOTSTRAP_PROFILE_FILE" ]] && read -r p < "$NS_BOOTSTRAP_PROFILE_FILE"
    echo "$p"
}

_ns_setting_default() {   # KEY PROFILE
    case "$1:$2" in
        NS_BOOTSTRAP_EXTRA_APPS:work)   echo off ;;
        NS_BOOTSTRAP_EXTRA_APPS:*)      echo on ;;
        NS_BOOTSTRAP_DAILY_UPDATE:work) echo off ;;
        NS_BOOTSTRAP_DAILY_UPDATE:*)    echo on ;;
        NS_BOOTSTRAP_DAILY_SCOPE:work)  echo formulae ;;
        NS_BOOTSTRAP_DAILY_SCOPE:*)     echo all ;;
        HOMEBREW_NO_ANALYTICS:work)     echo 1 ;;
        NS_BOOTSTRAP_OP_VAULT:*)        echo Personal ;;
        NS_BOOTSTRAP_SECRETS_PROVIDER:work) echo none ;;
        NS_BOOTSTRAP_GIT_SIGNING:work)  echo none ;;
        *)                              echo "" ;;
    esac
}

# Prints "SOURCE VALUE", SOURCE being environment, settings or default.
_ns_setting_lookup() {    # KEY [PROFILE]
    local key="$1" profile="${2:-$(ns_remembered_profile)}" value
    value="$(printenv "$key" 2>/dev/null || true)"
    if [[ -n "$value" ]]; then
        echo "environment ${value}"
        return
    fi
    if [[ -f "$NS_BOOTSTRAP_SETTINGS_FILE" ]]; then
        value="$(sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" "$NS_BOOTSTRAP_SETTINGS_FILE" \
            | tail -n 1 | sed -e 's/[[:space:]]#.*$//' -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/")"
        if [[ -n "$value" ]]; then
            echo "settings ${value}"
            return
        fi
    fi
    echo "default $(_ns_setting_default "$key" "$profile")"
}

ns_setting() {            # KEY [PROFILE]: the value
    local r
    r="$(_ns_setting_lookup "$@")"
    echo "${r#* }"
}

ns_setting_path() {       # KEY [PROFILE]: the value, a leading ~ expanded
    local v
    v="$(ns_setting "$@")"
    echo "${v/#\~/$HOME}"
}

ns_setting_source() {     # KEY [PROFILE]: environment, settings or default
    local r
    r="$(_ns_setting_lookup "$@")"
    echo "${r%% *}"
}

# Prints one line per invalid setting for PROFILE; returns 1 if any.
ns_settings_check() {     # PROFILE
    local profile="$1" key value bad=0
    # A literal list: zsh does not split an unquoted variable into words.
    # HOMEBREW_NO_ANALYTICS is Homebrew's own: any value turns analytics off.
    for key in NS_BOOTSTRAP_EXTRA_APPS NS_BOOTSTRAP_DAILY_UPDATE NS_BOOTSTRAP_DAILY_SCOPE \
               NS_BOOTSTRAP_BREWFILE_LOCAL; do
        value="$(ns_setting "$key" "$profile")"
        case "$key" in
            NS_BOOTSTRAP_EXTRA_APPS|NS_BOOTSTRAP_DAILY_UPDATE)
                [[ "$value" == on || "$value" == off ]] || { echo "${key} must be on or off, not '${value}'"; bad=1; } ;;
            NS_BOOTSTRAP_DAILY_SCOPE)
                [[ "$value" == all || "$value" == formulae ]] || { echo "${key} must be all or formulae, not '${value}'"; bad=1; } ;;
            NS_BOOTSTRAP_BREWFILE_LOCAL)
                value="${value/#\~/$HOME}"
                [[ -z "$value" || -f "$value" ]] || { echo "${key} names no file: ${value}"; bad=1; } ;;
        esac
    done
    if [[ "$profile" == work ]]; then
        value="$(ns_setting NS_BOOTSTRAP_SECRETS_PROVIDER work)"
        [[ "$value" == none || "$value" == 1password ]] \
            || { echo "NS_BOOTSTRAP_SECRETS_PROVIDER must be none or 1password for work, not '${value}'"; bad=1; }
        value="$(ns_setting NS_BOOTSTRAP_GIT_SIGNING work)"
        case "$value" in none|ssh-file|1password|gpg) ;;
            *) echo "NS_BOOTSTRAP_GIT_SIGNING must be none, ssh-file, 1password or gpg, not '${value}'"; bad=1 ;;
        esac
    fi
    if [[ "$profile" == work && "$(ns_setting NS_BOOTSTRAP_EXTRA_APPS work)" == on ]]; then
        echo "NS_BOOTSTRAP_EXTRA_APPS cannot be on for the work profile: those apps are personal or need a business licence"
        bad=1
    fi
    return "$bad"
}
