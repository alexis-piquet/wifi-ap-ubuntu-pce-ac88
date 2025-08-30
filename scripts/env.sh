#!/usr/bin/env bash
set -euo pipefail

CURRENT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_PATH/../lib/utils.sh"
source_as "$CURRENT_PATH/../lib/logger.sh" "LOGGER"

init_env() {
  LOGGER info "Ensuring NetworkManager is running and interfaces are managed"

  sudo systemctl enable --now NetworkManager

  if grep -q "managed=false" /etc/NetworkManager/NetworkManager.conf 2>/dev/null; then
    LOGGER warn "'managed=false' found in NetworkManager.conf — switching to 'managed=true'"
    sudo sed -i 's/managed=false/managed=true/' /etc/NetworkManager/NetworkManager.conf
    sudo systemctl restart NetworkManager
  fi

  LOGGER step "Detecting interfaces via nmcli"
  ethernet_id=$(nmcli dev status | awk '$2 == "ethernet" && $3 != "unavailable" {print $1}' | head -n1 || true)
  wireless_id=$(nmcli dev status | awk '$2 == "wifi" && $3 != "unavailable" {print $1}' | head -n1 || true)

  if [[ -z "$ethernet_id" ]]; then
    LOGGER error "Ethernet interface not found or still unmanaged"
    nmcli device status
    exit 1
  fi

  if [[ -z "$wireless_id" ]]; then
    LOGGER warn "Wi-Fi interface not found (yet) — this may be expected before firmware setup"
  fi

  LOGGER step "Checking for bridge (br0)"
  bridge_id=""

  if ! ip link show br0 &>/dev/null; then
    LOGGER info "Creating bridge br0 and attaching $ethernet_id"

    sudo nmcli connection delete br0 &>/dev/null || true
    sudo nmcli connection delete "bridge-slave-$ethernet_id" &>/dev/null || true

    sudo nmcli connection add type bridge ifname br0 con-name br0
    sudo nmcli connection add type ethernet con-name "bridge-slave-$ethernet_id" ifname "$ethernet_id" master br0

    for i in {1..5}; do
      if ip link show br0 &>/dev/null; then
        break
      fi
      LOGGER info "Waiting for br0 to appear..."
      sleep 1
    done

    sudo nmcli connection up "bridge-slave-$ethernet_id" || {
      LOGGER error "Failed to bring up bridge slave"
      exit 1
    }

    sudo nmcli connection up br0 || {
      LOGGER error "Failed to bring up bridge br0"
      nmcli connection show
      exit 1
    }

    bridge_id="br0"
  else
    LOGGER info "Bridge already exists: br0"
    bridge_id="br0"
  fi

  LOGGER info "Ethernet: $ethernet_id"
  LOGGER info "Wireless: $wireless_id"
  LOGGER info "Bridge: $bridge_id"

  printf "export ethernet_id=%s\nexport wireless_id=%s\nexport bridge_id=%s\n" \
    "$ethernet_id" "$wireless_id" "$bridge_id" > .env

  LOGGER ok "Environment written to .env"
}
