#!/usr/bin/env bash
# Network utility functions

# Scan top 20 ports on a target
function network_scan_20ports() {
  sudo nmap --top-ports 20 "$1"
}

# Scan top 20 ports on IPv6 target
function network_scan_20ports_ipv6() {
  sudo nmap --top-ports 20 -6 "$1"
}

# Bypass VPN for a specific IP (route via default gateway)
vpn_bypass() {
  local gateway
  if [[ "$OSTYPE" == "darwin"* ]]; then
    gateway=$(netstat -nr | grep default | head -n 1 | awk '{ print $2 }')
    sudo route -nv add "$1" "$gateway"
  else
    gateway=$(ip route | grep default | head -n 1 | awk '{ print $3 }')
    sudo ip route add "$1" via "$gateway"
  fi
}
