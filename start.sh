#!/usr/bin/env bash
set -euo pipefail

CURRENT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_PATH/lib/utils.sh"

export LOG_NAMESPACE="[START]"
source_as "$CURRENT_PATH/lib/log.sh" "LOGGER"

start() {
  LOGGER section "STARTING WI-FI ACCESS POINT"

  if [[ -f "$CURRENT_PATH/.env" ]]; then
    source "$CURRENT_PATH/.env"
  else
    LOGGER error "Missing .env file – cannot proceed"
    exit 1
  fi

  LOGGER step "Enabling IPv4 forwarding (runtime)"
  sudo sysctl -w net.ipv4.ip_forward=1

  LOGGER step "Ensuring NAT is configured"
  sudo iptables -t nat -C POSTROUTING -o "$ethernet_id" -j MASQUERADE 2>/dev/null || {
    sudo iptables -t nat -A POSTROUTING -o "$ethernet_id" -j MASQUERADE
    info "NAT rule added to iptables"
  }

  LOGGER step "Restarting NetworkManager"
  sudo systemctl restart NetworkManager

  LOGGER step "Cleaning iptables rules using ipsets"

  sudo iptables -t nat -D PREROUTING -m set --match-set allow_all dst -j RETURN 2>/dev/null || true
  sudo iptables -t nat -D PREROUTING -m set --match-set whitelist dst -j RETURN 2>/dev/null || true

  LOGGER step "Cleaning existing ipsets before restore"
  for setname in allow_all whitelist; do
    if sudo ipset list "$setname" &>/dev/null; then
      sudo ipset flush "$setname" || true
      sudo ipset destroy "$setname" || true
    fi
  done

  LOGGER step "Restarting dnsmasq (via NetworkManager)"
  sudo systemctl restart systemd-resolved

  LOGGER step "Setting regulatory domain and checking 5GHz availability"
  sudo iw reg set FR

  LOGGER step "Starting hostapd service"
  sudo systemctl restart hostapd

  LOGGER step "Active iptables rules (nat + filter)"
  sudo iptables -L -n -v --line-numbers
  sudo iptables -t nat -L -n -v --line-numbers

  LOGGER step "Active ipsets"
  sudo ipset list

  sleep 2

  # Check service status
  if systemctl is-active --quiet hostapd; then
    LOGGER ok "hostapd is running"
  else
    LOGGER error "hostapd failed to start"
    sudo journalctl -u hostapd --no-pager -n 20
    exit 1
  fi

  LOGGER step "Checking interface IP assignment"
  ip addr show "$wireless_id" | grep "inet " || warn "$wireless_id has no IP assigned"

  LOGGER step "Connected clients on $wireless_id"
  sudo iw dev "$wireless_id" station dump || LOGGER info "No clients connected"

  LOGGER ok "Access point is up and running"
}