#!/usr/bin/env bash
# macOS-specific functions
# Only loaded on macOS via shell/loader.sh

function shutdown_mac_now() {
  sudo shutdown -r now
}

function brew_cask_debug() {
  brew cask install "$1" --force --verbose --debug
}

# Network
function network_restart_launchctl() {
  sudo launchctl stop com.apple.wifid
  sudo launchctl start com.apple.wifid
}

function network_restart_ifconfig() {
  sudo ifconfig en0 down
  sudo ifconfig en0 up
  ifconfig -u en0
}

alias restart_en0='sudo ifconfig en0 down && sudo ifconfig en0 up'

# MAC address management
function mac_address_view() {
  sudo ifconfig en0 | awk '/ether/{print $2}'
}

function mac_address_change() {
  sudo /System/Library/PrivateFrameworks/Apple80211.framework/Resources/airport -z
  sudo ifconfig en0 ether $(openssl rand -hex 6 | sed 's/\(..\)/\1:/g; s/./0/2; s/.$//')
  networksetup -detectnewhardware
}

function mac_address_reset() {
  if [[ -z "${MAC_ADDRESS:-}" ]]; then
    echo "No stored MAC address found. Add it to ~/.config/ns-bootstrap/config:"
    echo "  MAC_ADDRESS=\"aa:bb:cc:dd:ee:ff\""
    return 1
  fi
  sudo ifconfig en0 ether "$MAC_ADDRESS"
}

function dns_flush() {
  sudo dscacheutil -flushcache
}

function audio_reset() {
  sudo kill -9 $(ps ax | grep 'coreaudio[a-z]' | awk '{print $1}')
}

# Disk image creation
function hdiutil_create_image() {
  local srcfolder="$1"
  local archive_name="$2"
  sudo hdiutil create \
    $archive_name \
    -srcfolder $srcfolder \
    -format UDZO
}

function user_backup_dmg() {
  local srcfolder="$1"
  local archive_name="$2"
  sudo hdiutil create \
    $archive_name \
    -srcfolder $srcfolder \
    -format UDIF \
    -verbose
}

# Finder hidden files
function show_hidden() {
  defaults write com.apple.finder AppleShowAllFiles $1
  echo -e "exit status: $(echo $?)\n"
}

# Disk verification
function disk_verify() {
  disk_path="$1"
  sudo diskutil verifyVolume $disk_path
}

# Chrome profile management
function google_chrome_nsjunk4() {
  open -a "Google Chrome" --args --profile-directory="Profile 5" --explicitly-allowed-ports=119,563
}

function chrome_list_profiles() {
  SAVEIFS=$IFS
  IFS=$(echo -en "\n\b")
  for item in $(ls -1 "${HOME}/Library/Application Support/Google/Chrome/"*/Preferences); do
    cat "$item" | jq -r "{ProfileName: .profile.name, ProfilePath: \"$item\"}"
  done
  IFS=$SAVEIFS
}

# Time Machine
function timemachine() {
  echo "
    tmutil listlocalsnapshots /
    tmutil deletelocalsnapshots 2020-05-01-085636

    tmutil listbackups
    tmutil delete /Volumes/xen_t5/Backups.backupdb/panda-mac/2020-01-11-031604"
}

# Disable macOS sleep
function disable_macos_sleep() {
  sudo pmset -a sleep 0; sudo pmset -a hibernatemode 0; sudo pmset -a disablesleep 1
}

# Shared permissions
alias shared_perms='sudo /bin/bash -c "chown -R $(whoami):shared /Users/Shared; chmod -R 2775 /Users/Shared"'

# Homebrew token — only needed if you hit GitHub API rate limits
# Usage: brew-auth   (fetches token from 1Password, exports for current session)
brew-auth() {
  if command -v get_homebrew_token &>/dev/null; then
    local token
    token=$(get_homebrew_token 2>/dev/null || echo "")
    if [[ -n "$token" ]]; then
      export HOMEBREW_GITHUB_API_TOKEN="$token"
      echo "HOMEBREW_GITHUB_API_TOKEN set for this session"
    else
      echo "Could not retrieve Homebrew token" >&2
      return 1
    fi
  else
    echo "get_homebrew_token not available" >&2
    return 1
  fi
}
