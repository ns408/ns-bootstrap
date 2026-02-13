#!/usr/bin/env bash
# Scheduled: Background daily update (no interaction needed)
# Called by launchd (macOS) or systemd timer (Ubuntu)
#
# macOS: runs update-brew-daily (formulae only, no sudo)
# Ubuntu: runs update-apt-daily (apt update/upgrade, needs sudo)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source platform-specific update functions
if [[ "$OSTYPE" == "darwin"* ]]; then
    source "${PROJECT_ROOT}/shell/platform/macos/update-system.sh"
    update-brew-daily
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    source "${PROJECT_ROOT}/shell/platform/ubuntu/update-system.sh"
    update-apt-daily
fi
