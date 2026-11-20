#!/usr/bin/env bash
# Install or upgrade the Rust CLI tools listed in packages/binstall-tools.ubuntu
# as prebuilt binaries into ~/.local/bin, taken only from each project's own
# GitHub release. Bootstrap (install-modern-tools.sh) and update-my-system both
# run this, so a tool is installed and upgraded by the same rules.
#
# Two cargo-binstall strategies are refused:
# - compile: a source build needs a whole Rust toolchain and minutes per tool.
# - quick-install: binaries built by a third party (cargo-quickinstall), not
#   by the tool's authors. It also lags new releases: on 2026-11-19 it had no
#   build of git-delta 0.21.1, released that day, so every install failed.
#
# cargo-binstall finds most release assets by guessing their names from the
# crate. Where a project names its assets differently, the URL is given below.
#
# Exits non-zero if any tool failed; the others are still installed.
set -uo pipefail

LIST="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/packages/binstall-tools.ubuntu"

failed=()
while IFS= read -r crate; do
    [[ -z "$crate" || "$crate" == \#* ]] && continue
    case "$crate" in
        git-delta)
            # Crate git-delta, assets delta-<version>-<target>.tar.gz, tag without a v.
            asset=(--pkg-fmt tgz
                --pkg-url '{ repo }/releases/download/{ version }/delta-{ version }-{ target }{ archive-suffix }'
                --bin-dir 'delta-{ version }-{ target }/{ bin }{ binary-ext }')
            ;;
        procs)
            # Assets procs-v<version>-<arch>-linux.zip, with no libc in the name.
            asset=(--pkg-fmt zip
                --pkg-url '{ repo }/releases/download/v{ version }/procs-v{ version }-{ target-arch }-linux{ archive-suffix }'
                --bin-dir '{ bin }{ binary-ext }')
            ;;
        *) asset=() ;;
    esac
    if ! cargo-binstall --no-confirm --disable-strategies compile,quick-install \
        --root "${HOME}/.local" "${asset[@]}" "$crate"; then
        echo "cargo-binstall ${crate} failed; continuing" >&2
        failed+=("$crate")
    fi
done < "$LIST"

if [[ ${#failed[@]} -gt 0 ]]; then
    echo "Rust CLI tools that failed: ${failed[*]}" >&2
    exit 1
fi
