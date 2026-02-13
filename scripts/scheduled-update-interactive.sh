#!/usr/bin/env bash
# Scheduled: Interactive daily update in tmux session
# Called by launchd (macOS) or systemd timer (Ubuntu)
#
# Opens a tmux session named "update" so you can see progress and
# respond to any sudo prompts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Only run for admin account on macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
    # Check if current user is an admin
    if ! dseditgroup -o checkmember -m "$(whoami)" admin &>/dev/null; then
        echo "Skipping: not an admin user"
        exit 0
    fi
fi

# Require tmux
if ! command -v tmux &>/dev/null; then
    echo "tmux not found, running directly..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        source "${PROJECT_ROOT}/shell/platform/macos/update-system.sh"
    else
        source "${PROJECT_ROOT}/shell/platform/ubuntu/update-system.sh"
    fi
    update-my-system
    exit $?
fi

SESSION_NAME="update"

# If session already exists, skip (previous run still active)
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "Update session already running, skipping"
    exit 0
fi

# Determine which source file and function to call
if [[ "$OSTYPE" == "darwin"* ]]; then
    SOURCE_FILE="${PROJECT_ROOT}/shell/platform/macos/update-system.sh"
else
    SOURCE_FILE="${PROJECT_ROOT}/shell/platform/ubuntu/update-system.sh"
fi

# Start detached tmux session running update-my-system
tmux new-session -d -s "$SESSION_NAME" \
    "source '${SOURCE_FILE}' && update-my-system; echo ''; echo 'Update complete. Press Enter to close.'; read"
