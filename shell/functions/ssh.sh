#!/usr/bin/env bash
# SSH utility functions

alias ssh_clear_sockets="rm -f ~/.ssh/sockets/*"

# Extract public key from private key and copy to clipboard
ssh_public_key() {
  if command -v pbcopy &>/dev/null; then
    ssh-keygen -y -f "$1" | pbcopy
  elif command -v xclip &>/dev/null; then
    ssh-keygen -y -f "$1" | xclip -selection clipboard
  else
    ssh-keygen -y -f "$1"
    echo "(no clipboard tool found — output printed above)"
  fi
}

# Create ed25519 SSH key pair
function ssh_create_ssh_key_pair() {
  if [[ -z "$1" || -z "$2" ]]; then
    echo 'Usage: ssh_create_ssh_key_pair ${HOME}/.ssh/keys/personal/homeuse "home user"'
  else
    ssh-keygen -o -a 100 -t ed25519 -f "$1" -C "$2"
  fi
}

# Download files via rsync over SSH
function rsync_ssh_download() {
  local servername=$1
  local remotedir=$2
  local localdir=$3
  rsync -av --progress -h -e "ssh" "${servername}:${remotedir}" "${localdir}"
}

# Upload files via rsync over SSH
function rsync_ssh_upload() {
  local servername=$1
  local localdir=$2
  local remotedir=$3
  rsync --bwlimit=1500 -av --progress -h -e "ssh" "${localdir}" "${servername}:${remotedir}"
}

# Display SSH key fingerprint
ssh_fingerprint() {
  local filepath=$1
  ssh-keygen -lf "$filepath"
}

# Dynamic port forwarding (SOCKS5 tunnel)
function ssh_dynamic_port_forwarding() {
  local login="$1"
  ssh -v -nNT -D "*:40800" "$login"
}
