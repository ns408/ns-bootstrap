#!/usr/bin/env bash
# Scheduled: Background daily update (no interaction needed)
# Called by launchd on macOS: runs update-brew-daily (formulae only, no sudo).
#
# Ubuntu has no job here. Its daily security updates come from
# unattended-upgrades, which apt's own timer runs as root; a per-user job
# could not run apt, as sudo has no terminal to ask for a password on.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source platform-specific update functions
if [[ "$OSTYPE" == "darwin"* ]]; then
    source "${PROJECT_ROOT}/shell/platform/macos/update-system.sh"
    update-brew-daily
fi
