#!/usr/bin/env bash
# macOS system update functions
#
# Two tiers:
#   update-brew-daily   — Formulae only, no sudo, safe for background/launchd
#   update-my-system    — Full update (casks, mise, omz, softwareupdate list), may need sudo
#   update-macos-install — Actually install macOS updates (may reboot)
#
# Scheduled via launchd (see scripts/scheduled-update-*.sh)

_update_log_dir="${HOME}/.local/log"

# --- Tier 1: Background daily (no sudo) ---
update-brew-daily() {
  local log
  log="${_update_log_dir}/brew-daily-$(date +%Y%m%d).log"
  mkdir -p "$_update_log_dir"

  {
    echo "=== Brew Daily Update: $(date) ==="
    brew update
    brew upgrade
    echo "=== Done: $(date) ==="
  } 2>&1 | tee -a "$log"

  # Prune logs older than 14 days
  find "$_update_log_dir" -name "brew-daily-*.log" -mtime +14 -delete 2>/dev/null
}

# --- Tier 2: Interactive daily in tmux (may need sudo) ---
update-my-system() {
  local log
  log="${_update_log_dir}/update-system-$(date +%Y%m%d).log"
  mkdir -p "$_update_log_dir"

  {
    echo "=== System Update Started: $(date) ==="

    # Homebrew casks (non-self-updating apps only)
    echo -e "\n--- Homebrew Casks ---"
    brew upgrade --cask
    brew cleanup --prune=1
    brew autoremove

    # Mac App Store (requires GUI session — skip if running via su/SSH/launchd)
    if command -v mas &>/dev/null; then
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

    # oh-my-zsh
    if command -v omz &>/dev/null; then
      echo -e "\n--- oh-my-zsh ---"
      omz update --unattended
    fi

    # Microsoft apps
    local msupdate="/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app/Contents/MacOS/msupdate"
    if [[ -f "$msupdate" ]]; then
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
