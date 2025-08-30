#!/usr/bin/env bash
set -euo pipefail

CURRENT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_PATH/../lib/utils.sh"

export LOG_NAMESPACE="[SCRIPTS][NAT]"
source_as "$CURRENT_PATH/../lib/logger.sh" "LOGGER"

init_nat() {
  LOGGER info "Setting up NAT and IP forwarding"
  if [[ -f "$CURRENT_PATH/../.env" ]]; then
    source "$CURRENT_PATH/../.env"
  else
    LOGGER error "Missing .env file – cannot proceed"
    exit 1
  fi

  LOGGER step "Enabling IPv4 forwarding"
  sudo sysctl -w net.ipv4.ip_forward=1
  sudo sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf

  LOGGER step "Setting up iptables NAT rule"
  sudo iptables -t nat -A POSTROUTING -o $ethernet_id -j MASQUERADE

  LOGGER step "Installing iptables-persistent"
  sudo apt install -y iptables-persistent

  LOGGER ok "NAT and forwarding enabled and persistent"
}