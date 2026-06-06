#!/usr/bin/env bash
# Opt-in Ubuntu remote desktop: XFCE + xrdp, LAN-scoped via ufw.
#
# NOT run by bootstrap.sh. Installs a graphical desktop and an RDP server, then
# restricts port 3389 to the local subnet. For untrusted networks prefer an SSH
# tunnel (ssh -L 3389:localhost:3389 user@host) over the LAN firewall rule.
#
# Usage:
#   bash install/ubuntu/install-remote-desktop.sh           # interactive
#   bash install/ubuntu/install-remote-desktop.sh --yes     # no prompt
#   SUBNET=10.0.0.0/24 bash install/ubuntu/install-remote-desktop.sh
set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()  { echo -e "${RED}[ERR ]${NC} $1" >&2; }

ASSUME_YES=false
[[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]] && ASSUME_YES=true

# --- Guard: Ubuntu/apt only ---
if ! command -v apt-get &>/dev/null; then
    log_err "This script targets Ubuntu (apt not found). Aborting."
    exit 1
fi

# --- Resolve the interactive user (script calls sudo internally) ---
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
if [[ -z "$TARGET_HOME" ]]; then
    log_err "Could not resolve home directory for user '$TARGET_USER'."
    exit 1
fi

# --- Detect LAN subnet (override with SUBNET=...) ---
if [[ -z "${SUBNET:-}" ]]; then
    IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
    if [[ -n "$IFACE" ]]; then
        SUBNET=$(ip route show dev "$IFACE" 2>/dev/null | awk '/proto kernel/ {print $1; exit}')
    fi
fi
if [[ -z "${SUBNET:-}" ]]; then
    log_err "Could not auto-detect the LAN subnet. Re-run with SUBNET=<cidr>, e.g. SUBNET=192.168.1.0/24"
    exit 1
fi

# --- Confirmation ---
log_warn "This installs a desktop (XFCE) and an RDP server (xrdp)."
log_warn "Port 3389/tcp will be opened to: ${SUBNET}"
log_warn "Desktop session will be configured for user: ${TARGET_USER}"
if [[ "$ASSUME_YES" != true ]]; then
    read -r -p "Proceed? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || { log_info "Aborted."; exit 0; }
fi

# --- Desktop environment (XFCE: lightest, best xrdp compatibility) ---
log_info "Checking XFCE desktop..."
if dpkg -l xfce4 2>/dev/null | grep -q '^ii'; then
    log_info "XFCE already installed."
else
    log_info "Installing XFCE desktop (this pulls in several hundred MB)..."
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y xfce4 xfce4-goodies dbus-x11
    log_info "XFCE installed."
fi

# --- xrdp ---
log_info "Checking xrdp..."
if command -v xrdp &>/dev/null; then
    log_info "xrdp already installed."
else
    log_info "Installing xrdp..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y xrdp
    log_info "xrdp installed."
fi

# --- Session config: XFCE for the target user, cert group for xrdp ---
log_info "Configuring xrdp session for ${TARGET_USER}..."
if [[ -f "${TARGET_HOME}/.xsession" ]] && grep -q '^startxfce4' "${TARGET_HOME}/.xsession"; then
    log_info ".xsession already set to startxfce4."
else
    echo "startxfce4" | sudo tee "${TARGET_HOME}/.xsession" > /dev/null
    sudo chown "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.xsession"
    log_info "Wrote ${TARGET_HOME}/.xsession"
fi
# Fixes black-screen-on-login from cert permission errors (idempotent).
sudo usermod -aG ssl-cert xrdp

# --- Firewall: ufw, LAN-only, lockout-safe (allow SSH BEFORE enabling) ---
log_info "Configuring firewall (ufw)..."
if ! command -v ufw &>/dev/null; then
    log_info "Installing ufw..."
    sudo apt-get install -y ufw
fi
# Allow SSH first so enabling ufw can never strand a remote session.
sudo ufw allow 22/tcp comment 'SSH' > /dev/null
# Restrict RDP to the LAN subnet.
if sudo ufw status | grep -q "3389/tcp.*ALLOW.*${SUBNET}"; then
    log_info "ufw rule for 3389 from ${SUBNET} already present."
else
    sudo ufw allow from "${SUBNET}" to any port 3389 proto tcp comment 'xrdp LAN' > /dev/null
    log_info "Allowed 3389/tcp from ${SUBNET}."
fi
if sudo ufw status | grep -q '^Status: active'; then
    log_info "ufw already active."
else
    sudo ufw --force enable
    log_info "ufw enabled."
fi

# --- Enable service ---
log_info "Enabling xrdp service..."
sudo systemctl enable --now xrdp
sudo systemctl restart xrdp

# --- Summary ---
HOST_IP=$(ip -o -f inet addr show "${IFACE:-}" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
echo
log_info "Remote desktop ready."
log_info "  Service : $(systemctl is-active xrdp)"
log_info "  Listen  : 3389/tcp restricted to ${SUBNET}"
log_info "  Connect : RDP client (Microsoft Remote Desktop / Remmina) -> ${HOST_IP:-<host-ip>}:3389"
log_info "  Login   : user '${TARGET_USER}' with its system password"
echo
log_info "To revert:"
log_info "  sudo systemctl disable --now xrdp"
log_info "  sudo ufw delete allow from ${SUBNET} to any port 3389 proto tcp"
