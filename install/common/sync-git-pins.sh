#!/usr/bin/env bash
# Check out each repository listed in packages/git-pins at its pinned commit:
# oh-my-zsh, its custom plugins and the vim plugins. Bootstrap runs this for
# the first install and update-my-system runs it to follow pin bumps, so a
# machine only ever runs code the repo has pinned, never whatever an upstream
# default branch holds on the day.
#
# Exits non-zero if any repository could not be brought to its pin; the
# others are still processed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

PINS_FILE="${GIT_PINS_FILE:-${SCRIPT_DIR}/../../packages/git-pins}"
# Overridable so the tests can serve repositories from local paths.
URL_BASE="${GIT_PINS_URL_BASE:-https://github.com}"
# Records the pin list last applied in full, so shell/apply-git-pins.zsh can
# tell at shell start, without running anything, whether the pins have moved.
APPLIED="${XDG_CACHE_HOME:-${HOME}/.cache}/ns-bootstrap/git-pins.applied"

dest_for() {
    case "$1" in
        omz)        echo "${HOME}/.oh-my-zsh" ;;
        zsh-plugin) echo "${HOME}/.oh-my-zsh/custom/plugins/$2" ;;
        vim-plugin) echo "${HOME}/.vim/pack/plugins/start/$2" ;;
        *)          return 1 ;;
    esac
}

sync_repo() {
    local name="$1" repo="$2" commit="$3" dest="$4"
    local url="${URL_BASE}/${repo}" origin head depth=()

    if [[ ! "$commit" =~ ^[0-9a-f]{40}$ ]] || [[ "$commit" =~ ^0+$ ]]; then
        log_warn "${name}: no commit pinned yet — skipping"
        return 1
    fi

    if [[ ! -e "$dest" ]]; then
        mkdir -p "$(dirname "$dest")"
        git init --quiet "$dest"
        git -C "$dest" remote add origin "$url"
        depth=(--depth 1)
    elif [[ ! -d "${dest}/.git" ]]; then
        log_warn "${name}: ${dest} exists but is not a git checkout — skipping"
        return 1
    fi

    origin=$(git -C "$dest" remote get-url origin 2>/dev/null || true)
    if [[ "$origin" != "$url" && "$origin" != "${url}.git" ]]; then
        log_warn "${name}: origin is '${origin}', expected ${url} — skipping"
        return 1
    fi

    head=$(git -C "$dest" rev-parse -q --verify HEAD 2>/dev/null || true)
    if [[ "$head" == "$commit" ]]; then
        log_info "${name}: at ${commit:0:12}"
        return 0
    fi

    # Keep an existing shallow clone shallow (oh-my-zsh's own installer made
    # one); fetching with --depth into a full clone would make it shallow.
    if [[ -f "${dest}/.git/shallow" ]]; then depth=(--depth 1); fi
    if ! git -C "$dest" fetch --quiet ${depth[@]+"${depth[@]}"} origin "$commit"; then
        log_warn "${name}: could not fetch ${commit:0:12} from ${url}"
        return 1
    fi
    # Refuses rather than overwrites if local edits would be lost.
    if ! git -C "$dest" -c advice.detachedHead=false checkout --quiet --detach "$commit"; then
        log_warn "${name}: local changes in ${dest} block the checkout — left as is"
        return 1
    fi
    log_info "${name}: ${head:0:12}${head:+ → }${commit:0:12}"
}

# Read once: a git pull landing mid-run must not mix old and new pins, and the
# record written below has to be exactly the list that was applied.
pins=$(<"$PINS_FILE")

failed=0
# oh-my-zsh first: its checkout has to exist before plugins go inside it.
for kind in omz zsh-plugin vim-plugin; do
    while read -r k name repo commit; do
        [[ -z "$k" || "$k" == \#* || "$k" != "$kind" ]] && continue
        sync_repo "$name" "$repo" "$commit" "$(dest_for "$k" "$name")" || failed=1
    done <<< "$pins"
done

if [[ "$failed" -eq 0 ]]; then
    mkdir -p "$(dirname "$APPLIED")"
    printf '%s\n' "$pins" > "$APPLIED"
fi
exit "$failed"
