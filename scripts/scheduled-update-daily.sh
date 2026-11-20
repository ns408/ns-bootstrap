#!/usr/bin/env bash
# Scheduled: Background daily update (no interaction needed)
# Called by launchd on macOS: runs update-brew-daily (no sudo). It upgrades
# formulae, and casks too unless NS_BOOTSTRAP_DAILY_SCOPE=formulae.
#
# Ubuntu has no job here. Its daily security updates come from
# unattended-upgrades, which apt's own timer runs as root; a per-user job
# could not run apt, as sudo has no terminal to ask for a password on.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source platform-specific update functions
if [[ "$OSTYPE" == "darwin"* ]]; then
    export NS_BOOTSTRAP_DIR="${NS_BOOTSTRAP_DIR:-$PROJECT_ROOT}"
    # Switched off since the agent was installed: do nothing until bootstrap
    # runs again and removes the agent.
    source "${PROJECT_ROOT}/install/lib/settings.sh"
    if [[ "$(ns_setting NS_BOOTSTRAP_DAILY_UPDATE)" == off ]]; then
        echo "NS_BOOTSTRAP_DAILY_UPDATE=off; skipping"
        exit 0
    fi
    source "${PROJECT_ROOT}/shell/platform/macos/update-system.sh"
    update-brew-daily
fi
