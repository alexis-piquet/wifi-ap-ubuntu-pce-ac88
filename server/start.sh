#!/usr/bin/env bash
set -euo pipefail

# Load log functions and env
. lib/log.sh
. .env

section "STARTING WI-FI ACCESS POINT"

step "Enabling IPv4 forwarding (runtime)"
sudo sysctl -w net.ipv4.ip_forward=1

step "Ensuring NAT is configured"
sudo iptables -t nat -C POSTROUTING -o "$ethernet_id" -j MASQUERADE 2>/dev/null || {
  sudo iptables -t nat -A POSTROUTING -o "$ethernet_id" -j MASQUERADE
  info "NAT rule added to iptables"
}

step "Restarting NetworkManager"
sudo systemctl restart NetworkManager

step "Cleaning existing ipsets before restore"
if sudo ipset list allow_all &>/dev/null; then
  sudo ipset flush allow_all || true
  sudo ipset destroy allow_all || true
fi

if sudo ipset list whitelist &>/dev/null; then
  sudo ipset flush whitelist || true
  sudo ipset destroy whitelist || true
fi

step "Restoring ipset rules (runtime)"
if [[ -f /etc/ipset.conf ]]; then
  sudo ipset restore < /etc/ipset.conf
  ok "ipsets restored from /etc/ipset.conf"
else
  warn "No ipset.conf found — skipping restore"
fi

step "Restarting dnsmasq (via NetworkManager)"
sudo systemctl restart systemd-resolved

step "Starting hostapd service"
sudo systemctl restart hostapd

step "Active iptables rules (nat + filter)"
sudo iptables -L -n -v --line-numbers
sudo iptables -t nat -L -n -v --line-numbers

step "Active ipsets"
sudo ipset list

sleep 2

# Check service status
if systemctl is-active --quiet hostapd; then
  ok "hostapd is running"
else
  error "hostapd failed to start"
  sudo journalctl -u hostapd --no-pager -n 20
  exit 1
fi

step "Checking interface IP assignment"
ip addr show "$wireless_id" | grep "inet " || warn "$wireless_id has no IP assigned"

step "Connected clients on $wireless_id"
sudo iw dev "$wireless_id" station dump || info "No clients connected"

ok "Access point is up and running"
