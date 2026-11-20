#!/usr/bin/env bash
# macOS system update functions
#
# Two tiers:
#   update-brew-daily   : formulae, and casks unless NS_BOOTSTRAP_DAILY_SCOPE=formulae;
#                         no sudo, safe for background/launchd
#   update-my-system    — Full update (casks, mise, pinned omz and plugins, softwareupdate list), may need sudo
#   update-macos-install — Actually install macOS updates (may reboot)
#
# Scheduled via launchd (see scripts/scheduled-update-*.sh)

_update_log_dir="${HOME}/.local/log"

# NS_BOOTSTRAP_DAILY_SCOPE (install/lib/settings.sh): "all" upgrades formulae
# and casks, "formulae" leaves apps alone, as on a company Mac. Read in a
# subshell so the settings helpers stay out of the interactive shell.
_update_scope() {
  local lib="${NS_BOOTSTRAP_DIR:-${HOME}/ns-bootstrap}/install/lib/settings.sh"
  local scope=all
  [[ -f "$lib" ]] && scope="$(bash -c 'source "$1"; ns_setting NS_BOOTSTRAP_DAILY_SCOPE' _ "$lib")"
  [[ "$scope" == formulae ]] && echo formulae || echo all
}

# --- Tier 1: Background daily (no sudo) ---
update-brew-daily() {
  local log
  log="${_update_log_dir}/brew-daily-$(date +%Y%m%d).log"
  mkdir -p "$_update_log_dir"

  {
    echo "=== Brew Daily Update: $(date) ==="
    brew update || true
    if [[ "$(_update_scope)" == formulae ]]; then
      brew upgrade --formula
    else
      brew upgrade
    fi
    echo "=== Done: $(date) ==="
  } 2>&1 | tee -a "$log"

  # Prune logs older than 14 days
  find "$_update_log_dir" -name "brew-daily-*.log" -mtime +14 -delete 2>/dev/null
}

# --- Tier 2: Interactive daily in tmux (may need sudo) ---
update-my-system() {
  local log scope
  local sync_pins="${NS_BOOTSTRAP_DIR:-${HOME}/ns-bootstrap}/install/common/sync-git-pins.sh"
  scope="$(_update_scope)"
  log="${_update_log_dir}/update-system-$(date +%Y%m%d).log"
  mkdir -p "$_update_log_dir"

  {
    echo "=== System Update Started: $(date) ==="

    # Homebrew formulae (CLI tools) — refresh metadata then upgrade
    echo -e "\n--- Homebrew Formulae ---"
    brew update || true
    if [[ "$scope" == formulae ]]; then
      brew upgrade --formula
    else
      brew upgrade

      # Homebrew casks (GUI apps)
      echo -e "\n--- Homebrew Casks ---"
      brew upgrade --cask
    fi
    brew cleanup --prune=1
    brew autoremove

    # Apps outside Homebrew are left alone when the scope is formulae.
    if [[ "$scope" == formulae ]]; then
      echo -e "\nNS_BOOTSTRAP_DAILY_SCOPE=formulae: leaving apps (casks, App Store, Microsoft) alone"
    fi

    # Mac App Store (requires GUI session — skip if running via su/SSH/launchd)
    if [[ "$scope" == all ]] && command -v mas &>/dev/null; then
      echo -e "\n--- Mac App Store ---"
      if [[ -z "${SECURITYSESSIONID:-}" ]]; then
        echo "No GUI session (su/SSH/launchd), skipping mas"
      elif ! mas account &>/dev/null; then
        echo "Not signed in to App Store, skipping"
      else
        mas upgrade
      fi
    fi

    # mise-managed languages
    if command -v mise &>/dev/null; then
      echo -e "\n--- mise ---"
      mise self-update 2>/dev/null || true
      mise upgrade
    fi

    # oh-my-zsh, its plugins and the vim plugins: moved to the commits pinned in
    # packages/git-pins, never to whatever upstream holds today. Pins advance
    # through the monthly Git Pin Bump review, or by hand for an urgent fix.
    if [[ -f "$sync_pins" ]]; then
      echo -e "\n--- Pinned repositories (oh-my-zsh, plugins) ---"
      bash "$sync_pins" || echo "Some pinned repositories were not updated; see above"
    fi

    # Microsoft apps
    local msupdate="/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app/Contents/MacOS/msupdate"
    if [[ "$scope" == all && -f "$msupdate" ]]; then
      echo -e "\n--- Microsoft Apps ---"
      ("${msupdate}" --list | grep --silent "No updates available") || "${msupdate}" --install
    fi

    # macOS software updates (list only — use update-macos-install to apply)
    echo -e "\n--- macOS Software Update (available) ---"
    softwareupdate -l 2>&1 || true

    echo -e "\n=== Done: $(date) ==="
  } 2>&1 | tee -a "$log"

  # Prune logs older than 14 days
  find "$_update_log_dir" -name "update-system-*.log" -mtime +14 -delete 2>/dev/null
}

# --- Manual: Install macOS updates (may reboot) ---
update-macos-install() {
  echo "Installing macOS updates (may require restart)..."
  sudo softwareupdate -i -a
}
