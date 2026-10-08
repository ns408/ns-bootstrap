#!/usr/bin/env bash
# Proposes bumps for the push scanners' pins once a new release is old enough:
# the Ubuntu binaries (version and SHA256 per architecture, in
# install/ubuntu/install-ubuntu-extras.sh) and the container images (tag and
# digest, in dotfiles/git/hooks/pre-push). Before proposing anything it checks
# each new binary against the release's published checksums, Trivy's tarballs
# against their build attestation, and the binary inside each image against
# the release binary, so a bump is never trust-on-first-use.
#
# Prints each finding as Markdown, NUL-terminated; prints nothing when every
# pin is current. Used by .github/workflows/pin-check.yml.
#
#   COOLDOWN_DAYS  minimum release age before a bump is proposed (default 14)
#   EXTRAS, HOOK   the pinned files, overridable for tests
set -uo pipefail

COOLDOWN_DAYS=${COOLDOWN_DAYS:-14}
EXTRAS=${EXTRAS:-install/ubuntu/install-ubuntu-extras.sh}
HOOK=${HOOK:-dotfiles/git/hooks/pre-push}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

finding() { printf '%s\0' "$1"; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
days_since() {
    python3 -c 'import sys, datetime as d
t = d.datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00"))
print((d.datetime.now(d.timezone.utc) - t).days)' "$1"
}
# Copy one file out of an image without running it.
from_image() {  # IMAGE PLATFORM PATH OUT
    local c rc
    c=$(docker create --quiet --platform "$2" "$1") || return 1
    docker cp -q "$c:$3" "$4"
    rc=$?
    docker rm "$c" >/dev/null
    return $rc
}
image_digest() {  # IMAGE:TAG
    docker buildx imagetools inspect "$1" --format '{{json .Manifest}}' \
        | python3 -c 'import json, sys; print(json.load(sys.stdin)["digest"])'
}
# Whether a release is new, old enough, and so worth checking; prints why not.
due() {  # NAME PINNED_BINARY PINNED_IMAGE LATEST PUBLISHED
    if [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
        finding "- Could not read the $1 pins (Ubuntu: \`${2:-?}\`, image: \`${3:-?}\`, latest: \`${4:-?}\`). The check itself may need fixing."
        return 1
    fi
    if [ "$2" != "$3" ]; then
        finding "- The $1 pins disagree: Ubuntu installs **$2** but the push hook's image is **$3**. Bring them to the same release."
        return 1
    fi
    [ "$2" = "$4" ] && return 1
    local age
    age=$(days_since "$5")
    if [ "$age" -lt "$COOLDOWN_DAYS" ]; then
        echo "$1 $4 is ${age} days old; proposed once it is ${COOLDOWN_DAYS}." >&2
        return 1
    fi
}

# --- OSV-Scanner -------------------------------------------------------------
pinned=$(sed -n 's/^OSV_VERSION="\(.*\)"/\1/p' "$EXTRAS")
in_image=$(sed -n 's/^OSV_IMAGE="[^@]*:v\([^@]*\)@.*/\1/p' "$HOOK")
read -r latest published < <(gh release view --repo google/osv-scanner \
    --json tagName,publishedAt -q '"\(.tagName | ltrimstr("v")) \(.publishedAt)"')
if due OSV-Scanner "$pinned" "$in_image" "${latest:-}" "${published:-}"; then
    rel="https://github.com/google/osv-scanner/releases/download/v${latest}"
    image="ghcr.io/google/osv-scanner:v${latest}"
    problem="" values=""
    curl -fsSL "$rel/osv-scanner_SHA256SUMS" -o "$work/osv-sums" || problem="its checksums file could not be fetched"
    digest=$(image_digest "$image") || problem="${problem:-the image digest could not be read}"
    for arch in amd64 arm64; do
        [ -n "$problem" ] && break
        asset="osv-scanner_linux_${arch}"
        curl -fsSL "$rel/$asset" -o "$work/$asset" || { problem="\`$asset\` could not be fetched"; break; }
        want=$(awk -v f="$asset" '$2 == f {print $1}' "$work/osv-sums")
        got=$(sha "$work/$asset")
        [ -n "$want" ] && [ "$got" = "$want" ] || { problem="\`$asset\` does not match the published checksum"; break; }
        from_image "$image@$digest" "linux/$arch" /osv-scanner "$work/img-$arch" \
            && [ "$(sha "$work/img-$arch")" = "$got" ] \
            || { problem="the image's $arch binary differs from the release binary"; break; }
        values="${values}OSV_SHA256 ($arch): $got"$'\n'
    done
    if [ -n "$problem" ]; then
        finding "- OSV-Scanner ${latest} is available, but **${problem}**. Do not bump until this is understood."
    else
        finding "- OSV-Scanner is pinned at **${pinned}**; **${latest}** is available (released ${published%%T*}). Checksums verified, and the image's binaries match the release. In \`${EXTRAS}\` set \`OSV_VERSION=\"${latest}\"\` and the two \`OSV_SHA256\` values; in \`${HOOK}\` set \`OSV_IMAGE\`:"$'\n\n'"\`\`\`"$'\n'"${values}OSV_IMAGE=\"${image}@${digest}\""$'\n'"\`\`\`"
    fi
fi

# --- Trivy ---------------------------------------------------------------------
pinned=$(sed -n 's/^TRIVY_VERSION="\(.*\)"/\1/p' "$EXTRAS")
in_image=$(sed -n 's/^TRIVY_IMAGE="[^@]*:\([^@]*\)@.*/\1/p' "$HOOK")
read -r latest published < <(gh release view --repo aquasecurity/trivy \
    --json tagName,publishedAt -q '"\(.tagName | ltrimstr("v")) \(.publishedAt)"')
if due Trivy "$pinned" "$in_image" "${latest:-}" "${published:-}"; then
    rel="https://github.com/aquasecurity/trivy/releases/download/v${latest}"
    image="ghcr.io/aquasecurity/trivy:${latest}"
    problem="" values=""
    curl -fsSL "$rel/trivy_${latest}_checksums.txt" -o "$work/trivy-sums" || problem="its checksums file could not be fetched"
    digest=$(image_digest "$image") || problem="${problem:-the image digest could not be read}"
    for pair in amd64:Linux-64bit arm64:Linux-ARM64; do
        [ -n "$problem" ] && break
        arch=${pair%%:*} asset="trivy_${latest}_${pair#*:}.tar.gz"
        curl -fsSL "$rel/$asset" -o "$work/$asset" || { problem="\`$asset\` could not be fetched"; break; }
        want=$(awk -v f="$asset" '$2 == f {print $1}' "$work/trivy-sums")
        got=$(sha "$work/$asset")
        [ -n "$want" ] && [ "$got" = "$want" ] || { problem="\`$asset\` does not match the published checksum"; break; }
        gh attestation verify "$work/$asset" --repo aquasecurity/trivy >/dev/null 2>&1 \
            || { problem="\`$asset\` failed attestation verification"; break; }
        mkdir -p "$work/rel-$arch"
        tar -xzf "$work/$asset" -C "$work/rel-$arch" trivy
        from_image "$image@$digest" "linux/$arch" /usr/local/bin/trivy "$work/img-$arch" \
            && [ "$(sha "$work/img-$arch")" = "$(sha "$work/rel-$arch/trivy")" ] \
            || { problem="the image's $arch binary differs from the release binary"; break; }
        values="${values}TRIVY_SHA256 ($arch): $got"$'\n'
    done
    if [ -n "$problem" ]; then
        finding "- Trivy ${latest} is available, but **${problem}**. Do not bump until this is understood."
    else
        finding "- Trivy is pinned at **${pinned}**; **${latest}** is available (released ${published%%T*}). Checksums and attestations verified, and the image's binaries match the release. In \`${EXTRAS}\` set \`TRIVY_VERSION=\"${latest}\"\` and the two \`TRIVY_SHA256\` values; in \`${HOOK}\` set \`TRIVY_IMAGE\`:"$'\n\n'"\`\`\`"$'\n'"${values}TRIVY_IMAGE=\"${image}@${digest}\""$'\n'"\`\`\`"
    fi
fi
