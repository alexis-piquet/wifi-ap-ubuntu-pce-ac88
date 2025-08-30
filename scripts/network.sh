#!/usr/bin/env bash
set -euo pipefail

CURRENT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_PATH/../lib/utils.sh"

export LOG_NAMESPACE="[SCRIPTS][NETWORK]"
source_as "$CURRENT_PATH/../lib/logger.sh" "LOGGER"

init_network() {
  LOGGER info "Setting up NAT and IP forwarding"

  if [[ -f "$CURRENT_PATH/../.env" ]]; then
    source "$CURRENT_PATH/../.env"
  else
    LOGGER error "Missing .env file – cannot proceed"
    exit 1
  fi

  LOGGER info "Ensuring /etc/network/interfaces.d exists"
  sudo mkdir -p /etc/network/interfaces.d

  CONFIG_FILE="config/interfaces.d/$wireless_id"
  TARGET_FILE="/etc/network/interfaces.d/$wireless_id"

  if [[ ! -f "$CONFIG_FILE" ]]; then
    LOGGER warn "Missing $CONFIG_FILE – generating fallback config"
    cat <<EOF | sudo tee "$TARGET_FILE" > /dev/null
auto $wireless_id
iface $wireless_id inet static
  address 10.0.0.1
  netmask 255.255.255.0
EOF
  else
    LOGGER step "Copying $CONFIG_FILE to $TARGET_FILE"
    sudo cp "$CONFIG_FILE" "$TARGET_FILE"
  fi

  LOGGER step "Restarting network interface"

  if systemctl list-units --type=service | grep -q '^networking.service'; then
    sudo systemctl restart networking
  else
    LOGGER warn "networking.service not found – falling back to ifdown/ifup"
    sudo ifdown "$wireless_id" || true
    sudo ifup "$wireless_id" || true
  fi

  LOGGER ok "Static IP configured on $wireless_id"
}