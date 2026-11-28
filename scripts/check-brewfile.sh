#!/usr/bin/env bash
# Checks every formula and cask in the given Brewfiles against Homebrew and
# fails when one needs an edit: not found, disabled, deprecated (Homebrew
# disables a deprecated entry about a year later) or renamed. Prints one
# GitHub Actions ::error:: line per finding, saying what to change, and
# "ok" for each current entry. Taps, App Store apps and comments are skipped.
#
# Casks are looked up with --cask: a plain `brew info docker` finds the docker
# formula and passes a renamed docker cask.
#
# Used by .github/workflows/brew-check.yml. Needs brew and jq, and the
# Brewfile's taps already added.
#
#   scripts/check-brewfile.sh packages/Brewfile.minimal [BREWFILE...]
set -uo pipefail

[[ $# -gt 0 ]] || { echo "usage: $0 BREWFILE..." >&2; exit 2; }
for f in "$@"; do
    [[ -r "$f" ]] || { echo "$0: cannot read $f" >&2; exit 2; }
done

findings=0
err=$(mktemp)
trap 'rm -f "$err"' EXIT

# What needs changing for one entry, from brew's JSON; empty when current.
# WANT is the name as listed, without any tap prefix.
verdict() {  # WANT, JSON on stdin
    jq -r --arg want "$1" '
        (.formulae + .casks)[0]
        | (.name // .token) as $now
        | ([.disable_replacement_formula, .disable_replacement_cask,
            .deprecation_replacement_formula, .deprecation_replacement_cask]
           | map(select(. != null and . != "")) | first // "") as $rep
        | (if $rep == "" then "remove it" else "replace it with \($rep)" end) as $fix
        | if .disabled then
            "disabled since \(.disable_date // "unknown") (\(.disable_reason // "no reason given")); \($fix)"
          elif .deprecated then
            "deprecated since \(.deprecation_date // "unknown") (\(.deprecation_reason // "no reason given")), to be disabled; \($fix)"
          elif $now != $want and ((.oldnames // []) + (.old_tokens // []) | index($want)) then
            "renamed to \($now); use the new name"
          else "" end'
}

check() {  # FILE KIND NAME
    local file="$1" kind="$2" name="$3" flag json why reason rc
    [[ "$kind" == brew ]] && flag=--formula || flag=--cask
    json=$(brew info --json=v2 "$flag" "$name" 2>"$err")
    rc=$?
    if [[ "$rc" -ne 0 ]]; then
        # brew's first error line says why, such as a move to a cask; failing
        # that, its last line and exit code, such as a tap formula that
        # would not load.
        reason=$(grep -m1 '^Error: ' "$err" | sed 's/^Error: //')
        if [[ -n "$reason" ]]; then
            reason="brew: ${reason}"
        else
            reason="brew exit ${rc}$(grep -v '^[[:space:]]*$' "$err" | tail -n 1 | sed 's/^/: /')"
        fi
        why="not found in Homebrew (${reason}); remove it or list what replaced it"
    else
        why=$(verdict "${name##*/}" <<< "$json") || why="brew info gave JSON this check cannot read"
    fi
    if [[ -n "$why" ]]; then
        echo "::error file=${file}::${kind} \"${name}\": ${why}"
        findings=$((findings + 1))
    else
        echo "ok  ${kind} \"${name}\""
    fi
}

entry='^[[:space:]]*(brew|cask)[[:space:]]+"([^"]+)"'
for f in "$@"; do
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ $entry ]] && check "$f" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    done < "$f"
done

if [[ "$findings" -gt 0 ]]; then
    [[ "$findings" -eq 1 ]] && echo "1 entry needs a Brewfile edit" || echo "${findings} entries need a Brewfile edit"
    exit 1
fi
