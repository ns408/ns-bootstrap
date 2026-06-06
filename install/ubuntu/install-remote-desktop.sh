#!/usr/bin/env bash
# Opt-in Ubuntu remote desktop: XFCE + xrdp, LAN-scoped via ufw.
#
# NOT run by bootstrap.sh. Installs a graphical desktop and an RDP server, then
# restricts port 3389 to the local subnet. For untrusted networks prefer an SSH
# tunnel (ssh -L 3389:localhost:3389 user@host) over the LAN firewall rule.
#
# Desktop is selectable via DESKTOP=gnome|xfce|auto (default auto: use GNOME if
# already installed, else install XFCE). On a machine you already use with GNOME,
# the GNOME path avoids running two conflicting desktop environments.
#
# Usage:
#   bash install/ubuntu/install-remote-desktop.sh           # interactive
#   bash install/ubuntu/install-remote-desktop.sh --yes     # no prompt
#   DESKTOP=xfce bash install/ubuntu/install-remote-desktop.sh
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

# --- Choose desktop (DESKTOP=gnome|xfce|auto) ---
DESKTOP="${DESKTOP:-auto}"
if [[ "$DESKTOP" == "auto" ]]; then
    if command -v gnome-session &>/dev/null; then
        DESKTOP=gnome
    else
        DESKTOP=xfce
    fi
fi
case "$DESKTOP" in
    gnome|xfce) ;;
    *) log_err "Invalid DESKTOP='${DESKTOP}'. Use gnome, xfce, or auto."; exit 1 ;;
esac
if [[ "$DESKTOP" == "gnome" ]] && ! command -v gnome-session &>/dev/null; then
    log_err "DESKTOP=gnome but gnome-session is not installed."
    log_err "Install GNOME first (e.g. sudo apt install ubuntu-desktop-minimal) or use DESKTOP=xfce."
    exit 1
fi

# --- Confirmation ---
log_warn "This sets up remote desktop using: ${DESKTOP^^}"
[[ "$DESKTOP" == "xfce" ]] && log_warn "  XFCE will be installed (pulls in several hundred MB)."
[[ "$DESKTOP" == "gnome" ]] && log_warn "  Uses your existing GNOME (no XFCE installed)."
log_warn "An RDP server (xrdp) will run, port 3389/tcp opened to: ${SUBNET}"
log_warn "Desktop session will be configured for user: ${TARGET_USER}"
if [[ "$ASSUME_YES" != true ]]; then
    read -r -p "Proceed? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || { log_info "Aborted."; exit 0; }
fi

# --- Desktop environment ---
if [[ "$DESKTOP" == "xfce" ]]; then
    log_info "Checking XFCE desktop..."
    if dpkg -l xfce4 2>/dev/null | grep -q '^ii'; then
        log_info "XFCE already installed."
    else
        log_info "Installing XFCE desktop (this pulls in several hundred MB)..."
        sudo apt-get update
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y xfce4 xfce4-goodies dbus-x11
        log_info "XFCE installed."
    fi
else
    log_info "Using existing GNOME desktop (no XFCE install)."
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

# --- Disable xorgxrdp glamor (GPU) acceleration for broad compatibility ---
# On old/integrated GPUs glamor's EGL shaders fail to compile, breaking the
# framebuffer-to-client path and producing a black screen. Forcing software
# rendering is rock-solid everywhere and the cost is negligible for a 2D desktop
# over LAN.
XORG_CONF=/etc/X11/xrdp/xorg.conf
if [[ -f "$XORG_CONF" ]]; then
    if grep -q 'Option "DRMDevice" ""' "$XORG_CONF" && grep -q 'Option "DRI3" "0"' "$XORG_CONF"; then
        log_info "xorgxrdp glamor already disabled."
    else
        log_info "Disabling xorgxrdp glamor (software rendering) for GPU compatibility..."
        [[ -f "${XORG_CONF}.bak" ]] || sudo cp "$XORG_CONF" "${XORG_CONF}.bak"
        sudo sed -i -E 's|(Option +"DRMDevice" +)"[^"]*"|\1""|; s|(Option +"DRI3" +)"[^"]*"|\1"0"|' "$XORG_CONF"
        log_info "Glamor disabled in ${XORG_CONF}."
    fi
else
    log_warn "${XORG_CONF} not found; skipping glamor tweak."
fi

# --- Session config: write ~/.xsession for the chosen desktop ---
log_info "Configuring xrdp ${DESKTOP^^} session for ${TARGET_USER}..."
XS="${TARGET_HOME}/.xsession"
if [[ "$DESKTOP" == "gnome" ]]; then
    # GNOME over xrdp must run an Xorg (not Wayland) session.
    read -r -d '' XS_CONTENT <<'EOF' || true
export GNOME_SHELL_SESSION_MODE=ubuntu
export XDG_CURRENT_DESKTOP=ubuntu:GNOME
export XDG_SESSION_TYPE=x11
exec /usr/bin/gnome-session
EOF
else
    XS_CONTENT='exec startxfce4'
fi
if [[ -f "$XS" ]] && [[ "$(cat "$XS" 2>/dev/null)" == "$XS_CONTENT" ]]; then
    log_info ".xsession already configured for ${DESKTOP}."
else
    printf '%s\n' "$XS_CONTENT" | sudo tee "$XS" > /dev/null
    sudo chown "${TARGET_USER}:${TARGET_USER}" "$XS"
    log_info "Wrote ${XS}"
fi
# Fixes black-screen-on-login from cert permission errors (idempotent).
sudo usermod -aG ssl-cert xrdp

# --- Polkit: stop the colord "authentication required" popups over RDP ---
# (Known Ubuntu 24.04 regression; affects GNOME and XFCE remote sessions alike.)
POLKIT_RULE=/etc/polkit-1/rules.d/45-allow-colord.rules
if [[ -f "$POLKIT_RULE" ]]; then
    log_info "Polkit color-manager override already present."
else
    log_info "Installing polkit override to suppress color-profile auth popups..."
    sudo tee "$POLKIT_RULE" > /dev/null <<'EOF'
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.freedesktop.color-manager.") == 0) {
        return polkit.Result.YES;
    }
});
EOF
    sudo systemctl restart polkit 2>/dev/null || true
fi

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
log_info "  Desktop : ${DESKTOP^^}"
log_info "  Service : $(systemctl is-active xrdp)"
log_info "  Listen  : 3389/tcp restricted to ${SUBNET}"
log_info "  Connect : RDP client (Microsoft Remote Desktop / Remmina) -> ${HOST_IP:-<host-ip>}:3389"
log_info "  Login   : user '${TARGET_USER}' with its system password"
echo
log_warn "Do NOT be logged into the console as '${TARGET_USER}' at the same time:"
log_warn "  GNOME/XFCE refuse two simultaneous sessions for one user (black screen/crash)."
log_warn "  Check with: loginctl list-sessions"
if [[ "$DESKTOP" == "gnome" ]]; then
    log_warn "If GNOME shows a black screen (a known 24.04 Xorg-backend bug), pick the"
    log_warn "  'Xvnc' session from the dropdown on the xrdp login page instead of 'Xorg'."
fi
echo
log_info "To revert:"
log_info "  sudo systemctl disable --now xrdp"
log_info "  sudo ufw delete allow from ${SUBNET} to any port 3389 proto tcp"
