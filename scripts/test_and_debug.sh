#!/usr/bin/env bash
set -euo pipefail

CURRENT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_PATH/../lib/utils.sh"

export LOG_NAMESPACE="[SCRIPTS][TEST_AND_DEBUG]"
source_as "$CURRENT_PATH/../lib/logger.sh" "LOGGER"

init() {
  LOGGER info "Test and Debug"

  if [[ -f "$CURRENT_PATH/../.env" ]]; then
    source "$CURRENT_PATH/../.env"
  else
    LOGGER error "Missing .env file – cannot proceed"
    exit 1
  fi

  LOGGER step "IP addresses"
  ip a

  LOGGER step "DHCP check"
  nmcli dev show "$wireless_id" | grep IP4 || warn "No DHCP address?"

  LOGGER step "Connected clients"
  sudo iw dev "$wireless_id" station dump || info "No clients connected"

  LOGGER step "iptables NAT table"
  sudo iptables -t nat -L -n -v

  LOGGER step "Testing ipsets"
  sudo ipset list whitelist | head
  sudo ipset list allow_all | head

  LOGGER info "Testing DNS resolution (should be allowed):"
  dig example.com @127.0.0.1

  LOGGER info "Testing DNS resolution (should be blocked):"
  dig facebook.com @127.0.0.1

  LOGGER ok "Diagnostics completed"
}