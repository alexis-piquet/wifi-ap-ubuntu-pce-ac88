#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../lib/log.sh"

section "Check env"
step "Ensuring NetworkManager is running and interfaces are managed"

# Enable and start NetworkManager
sudo systemctl enable --now NetworkManager

# Fix unmanaged interfaces if needed
if grep -q "managed=false" /etc/NetworkManager/NetworkManager.conf 2>/dev/null; then
  warn "'managed=false' found in NetworkManager.conf — switching to 'managed=true'"
  sudo sed -i 's/managed=false/managed=true/' /etc/NetworkManager/NetworkManager.conf
  sudo systemctl restart NetworkManager
fi

step "Detecting interfaces via nmcli"
ethernet_id=$(nmcli dev status | awk '$2 == "ethernet" && $3 != "unavailable" {print $1}' | head -n1 || true)
wireless_id=$(nmcli dev status | awk '$2 == "wifi" && $3 != "unavailable" {print $1}' | head -n1 || true)

if [[ -z "$ethernet_id" ]]; then
  error "Ethernet interface not found or still unmanaged"
  nmcli device status
  exit 1
fi

if [[ -z "$wireless_id" ]]; then
  warn "Wi-Fi interface not found (yet) — this may be expected before firmware setup"
fi

step "Checking for bridge (br0)"
bridge_id=""

if ! ip link show br0 &>/dev/null; then
  info "Creating bridge br0 and attaching $ethernet_id"

  # Create bridge and attach Ethernet
  sudo nmcli connection add type bridge ifname br0 con-name br0
  sudo nmcli connection add type ethernet ifname "$ethernet_id" master br0
  sudo nmcli connection up br0
  bridge_id="br0"
else
  info "Bridge already exists: br0"
  bridge_id="br0"
fi

info  "Ethernet: $ethernet_id"
info  "Wireless: $wireless_id"
info  "Bridge: $bridge_id"

# Write .env file
printf "export ethernet_id=%s\nexport wireless_id=%s\nexport bridge_id=%s\n" \
  "$ethernet_id" "$wireless_id" "$bridge_id" > .env

ok "Environment written to .env"
