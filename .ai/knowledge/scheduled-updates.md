# Scheduled System Updates

## Two-Tier Strategy

Split updates into two tiers based on interactivity requirements:

| Tier | What | Needs Sudo | Interactive |
|------|------|------------|-------------|
| Background | Package manager formulae/packages | No (macOS brew) / Yes (Ubuntu apt) | No |
| Interactive | Casks, App Store, language managers, OS updates | Possibly | Yes (tmux session) |

## launchd (macOS)

Template plist files with variables, substitute at install time:

```xml
<key>ProgramArguments</key>
<array>
    <string>/bin/bash</string>
    <string>${PROJECT_ROOT}/scripts/scheduled-update-daily.sh</string>
</array>
```

Install with `sed` substitution:

```bash
sed -e "s|\${PROJECT_ROOT}|${PROJECT_ROOT}|g" \
    -e "s|\${HOME}|${HOME}|g" \
    template.plist > ~/Library/LaunchAgents/com.ns-bootstrap.update.plist
launchctl load ~/Library/LaunchAgents/com.ns-bootstrap.update.plist
```

Key behaviors:
- `StartCalendarInterval` auto-fires on wake if the Mac was asleep
- Per-user agents in `~/Library/LaunchAgents/` — only runs for that user
- Set `StandardOutPath`/`StandardErrorPath` for logging
- Include `PATH` in `EnvironmentVariables` (launchd has a minimal environment)

## systemd User Timers (Linux)

```ini
# ~/.config/systemd/user/my-update.timer
[Timer]
OnCalendar=*-*-* 07:00:00
Persistent=true          # Fire on next boot if missed

[Install]
WantedBy=timers.target
```

`%h` in service files expands to the user's home directory.

Enable: `systemctl --user enable --now my-update.timer`

## tmux Session Pattern

For interactive updates that may need user input (sudo, confirmations):

```bash
SESSION_NAME="update"

# Skip if already running
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "Update session already running"
    exit 0
fi

# Start detached — user attaches when ready
tmux new-session -d -s "$SESSION_NAME" \
    "source update-functions.sh && update-my-system; echo 'Done. Press Enter.'; read"
```

## Admin-Only Gate

On macOS with a two-account setup, only the admin account should run system updates:

```bash
if ! dseditgroup -o checkmember -m "$(whoami)" admin &>/dev/null; then
    echo "Skipping: not an admin user"
    exit 0
fi
```

## Log Management

Log each run with a date-stamped file, auto-prune old logs:

```bash
LOG_DIR="${HOME}/.local/log"
mkdir -p "$LOG_DIR"
LOG="${LOG_DIR}/update-$(date +%Y%m%d).log"

{ echo "=== Update: $(date) ==="; do_update; } 2>&1 | tee -a "$LOG"

find "$LOG_DIR" -name "update-*.log" -mtime +14 -delete 2>/dev/null
```
