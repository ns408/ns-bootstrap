# macOS Administration

## Two-Account Setup

Use separate admin and daily-driver accounts on macOS. The admin account handles Homebrew installs, system updates, and privileged operations. The daily account is non-admin for reduced attack surface.

Shared files (repos, data, configs) live in `/Users/Shared/` with ACL inheritance so both accounts can read/write:

```bash
sudo chmod -R +a \
  "group:staff allow list,add_file,search,add_subdirectory,delete_child,readattr,writeattr,readextattr,writeextattr,readsecurity,file_inherit,directory_inherit" \
  /Users/Shared/repositories
```

Check admin membership: `dseditgroup -o checkmember -m "$(whoami)" admin`

## Homebrew

- `HOMEBREW_BUNDLE_NO_LOCK=1 brew bundle` — prevents lockfile generation
- `brew analytics off` — disable anonymous usage tracking
- Homebrew prefix: `/opt/homebrew` (Apple Silicon only — Intel/Rosetta not supported)
- Detect at runtime: `$(brew --prefix)`

### Self-Updating Cask Pattern

Apps like Chrome, VS Code, Firefox, and 1Password have built-in updaters. Install them via brew once, then remove from Caskroom so Homebrew stops managing version conflicts:

```bash
brew install --cask google-chrome
rm -rf "$(brew --prefix)/Caskroom/google-chrome"
```

The app stays in `/Applications` but Homebrew no longer tracks it.

## launchd Scheduling

- `StartCalendarInterval` fires the job on wake if the Mac was asleep at the scheduled time
- Per-user agents go in `~/Library/LaunchAgents/`
- Template plist files with `${VARIABLE}` placeholders, substitute with `sed` at install time
- `launchctl load/unload` to manage agents

## Mac App Store CLI (mas)

- `mas` requires an active Aqua/GUI session — it cannot run from `su`, SSH, or launchd
- Detect GUI session via `SECURITYSESSIONID` environment variable (set by WindowServer login, absent in non-GUI contexts)
- Guard pattern: `[[ -z "${SECURITYSESSIONID:-}" ]] && echo "No GUI session" && return`
- `mas account` checks sign-in status without prompting

## softwareupdate

- `softwareupdate -l` lists available updates (safe, no changes)
- `softwareupdate -i -a` installs all (may require restart)
- Listing is safe for background/cron; installing should be interactive

## scutil (hostname)

```bash
sudo scutil --set HostName "my-machine"
sudo scutil --set ComputerName "my-machine"
sudo scutil --set LocalHostName "my-machine"
```

## FileVault & Firewall

```bash
sudo fdesetup enable                             # Full-disk encryption
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on  # Firewall
```
