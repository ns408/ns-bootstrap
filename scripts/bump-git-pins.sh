#!/usr/bin/env bash
# Move each pin in packages/git-pins to the commit its upstream default branch
# pointed at COOLDOWN_DAYS ago (default 14), going by GitHub's own record of
# when each push landed (the repository activity API). A commit's date is no
# use here: whoever makes the commit sets it, so a malicious commit can be
# backdated straight past any age check based on it.
#
# A pin is held back and flagged for review when:
#   - its branch was force-pushed in the last 90 days (history rewritten), or
#   - the candidate is not a descendant of the pin, or is no longer on the
#     branch (history no longer lines up).
# A pin already ahead of the candidate, bumped by hand for an urgent fix, is
# kept. An all-zero pin is unset, and takes the candidate as its first pin.
#
# Usage: scripts/bump-git-pins.sh [--report FILE]   (needs gh, authenticated, and jq)
set -euo pipefail

PINS_FILE="${GIT_PINS_FILE:-$(cd "$(dirname "$0")/.." && pwd)/packages/git-pins}"
COOLDOWN_DAYS="${COOLDOWN_DAYS:-14}"
REPORT=/dev/stdout
if [[ "${1:-}" == "--report" ]]; then REPORT="$2"; fi

cutoff=$(jq -nr --argjson d "$COOLDOWN_DAYS" 'now - $d * 86400 | todate')
force_window=$(jq -nr 'now - 90 * 86400 | todate')
zeros=0000000000000000000000000000000000000000

bumps=()
held=()

# activity <repo> <branch> [extra query]: activity on the branch as one JSON array.
activity() {
    gh api --paginate "repos/$1/activity?ref=refs/heads/$2&per_page=100$3" --jq '.[]' | jq -s .
}

lineno=0
while IFS= read -r line; do
    lineno=$((lineno + 1))
    read -r kind name repo pin <<< "$line" || true
    [[ -z "${kind:-}" || "$kind" == \#* ]] && continue

    branch=$(gh api "repos/${repo}" --jq .default_branch)
    ref="refs/heads/${branch}"
    year=$(activity "$repo" "$branch" "&time_period=year")

    # The branch as it stood at the cutoff: the newest push at or before it.
    # Quiet repos may have nothing that recent, so fall back to the full record.
    pick='[.[] | select(.ref == $ref and .timestamp <= $cutoff)] | max_by(.timestamp) // empty
          | "\(.after) \(.timestamp[:10])"'
    found=$(jq -r --arg ref "$ref" --arg cutoff "$cutoff" "$pick" <<< "$year")
    if [[ -z "$found" ]]; then
        found=$(gh api "repos/${repo}/activity?ref=${ref}&per_page=100" \
            | jq -r --arg ref "$ref" --arg cutoff "$cutoff" "$pick")
    fi
    read -r candidate landed <<< "${found:-}" || true

    if [[ -z "${candidate:-}" || "$candidate" == "$zeros" ]]; then
        held+=("| \`${repo}\` | No push old enough on \`${branch}\` to pin to |")
        continue
    fi

    forced=$(jq -r --arg ref "$ref" --arg since "$force_window" \
        '[.[] | select(.ref == $ref and .activity_type == "force_push" and .timestamp > $since)
              | .timestamp[:10]] | max // empty' <<< "$year")
    if [[ -n "$forced" ]]; then
        held+=("| \`${repo}\` | \`${branch}\` was force-pushed on ${forced}: history was rewritten, so review it before moving the pin |")
        continue
    fi

    # Still reachable from the branch tip, i.e. not rewritten away?
    on_branch=$(gh api "repos/${repo}/compare/${candidate}...${branch}" --jq .status)
    if [[ "$on_branch" != "identical" && "$on_branch" != "ahead" ]]; then
        held+=("| \`${repo}\` | \`${candidate:0:12}\` is no longer on \`${branch}\` (${on_branch}) |")
        continue
    fi

    if [[ "$pin" == "$zeros" ]]; then
        commits="first pin"
        diff="[${candidate:0:12}](https://github.com/${repo}/commit/${candidate})"
    else
        read -r status commits <<< "$(gh api "repos/${repo}/compare/${pin}...${candidate}" \
            --jq '"\(.status) \(.total_commits)"')"
        case "$status" in
            identical) continue ;;
            behind)    continue ;;   # pinned ahead by hand; keep it
            ahead)     diff="[compare](https://github.com/${repo}/compare/${pin}...${candidate})" ;;
            *)
                held+=("| \`${repo}\` | Pin \`${pin:0:12}\` and candidate \`${candidate:0:12}\` have ${status} |")
                continue ;;
        esac
    fi

    sed -i.bak "${lineno}s/${pin}/${candidate}/" "$PINS_FILE" && rm -f "${PINS_FILE}.bak"
    bumps+=("| \`${repo}\` | \`${pin:0:12}\` → \`${candidate:0:12}\` | ${commits} | ${landed} | ${diff} |")
    echo "bumped ${name}: ${pin:0:12} -> ${candidate:0:12} (${commits})" >&2
done < "$PINS_FILE"

{
    echo "Pins moved to the commit each upstream branch held ${COOLDOWN_DAYS} days ago, by GitHub's push records (cutoff ${cutoff})."
    echo
    if [[ ${#bumps[@]} -gt 0 ]]; then
        echo "| Repository | Pin | Commits | On the branch since | Changes |"
        echo "|---|---|---|---|---|"
        printf '%s\n' "${bumps[@]}"
    else
        echo "No pins to move."
    fi
    if [[ ${#held[@]} -gt 0 ]]; then
        echo
        echo "**Held back for review**"
        echo
        echo "| Repository | Reason |"
        echo "|---|---|"
        printf '%s\n' "${held[@]}"
    fi
} > "$REPORT"
