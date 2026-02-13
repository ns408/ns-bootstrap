#!/usr/bin/env bash
# Ubuntu system update functions
#
# Two tiers:
#   update-apt-daily    — apt packages only, background-safe
#   update-my-system    — Full update (snap, flatpak, mise, omz), may need sudo
#
# Scheduled via systemd user timers (see scripts/scheduled-update-*.sh)

_update_log_dir="${HOME}/.local/log"

# --- Tier 1: Background daily (needs sudo for apt) ---
update-apt-daily() {
  local log="${_update_log_dir}/apt-daily-$(date +%Y%m%d).log"
  mkdir -p "$_update_log_dir"

  {
    echo "=== APT Daily Update: $(date) ==="
    sudo apt update
    sudo apt upgrade -y
    sudo apt autoremove -y
    echo "=== Done: $(date) ==="
  } 2>&1 | tee -a "$log"

  # Prune logs older than 14 days
  find "$_update_log_dir" -name "apt-daily-*.log" -mtime +14 -delete 2>/dev/null
}

# --- Tier 2: Interactive daily (full system) ---
update-my-system() {
  local log="${_update_log_dir}/update-system-$(date +%Y%m%d).log"
  mkdir -p "$_update_log_dir"

  {
    echo "=== System Update Started: $(date) ==="

    # Snap packages
    if command -v snap &>/dev/null; then
      echo -e "\n--- Snap ---"
      sudo snap refresh
    fi

    # Flatpak packages
    if command -v flatpak &>/dev/null; then
      echo -e "\n--- Flatpak ---"
      flatpak update -y
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

    # Pending security updates
    echo -e "\n--- Security Updates (available) ---"
    if command -v unattended-upgrade &>/dev/null; then
      sudo unattended-upgrade --dry-run 2>&1 || true
    else
      apt list --upgradable 2>/dev/null || true
    fi

    echo -e "\n=== Done: $(date) ==="
  } 2>&1 | tee -a "$log"

  # Prune logs older than 14 days
  find "$_update_log_dir" -name "update-system-*.log" -mtime +14 -delete 2>/dev/null
}
