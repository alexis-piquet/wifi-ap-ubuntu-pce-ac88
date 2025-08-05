#!/usr/bin/env bash
set -euo pipefail

# Load helpers and environment variables
. lib/log.sh
. .env

section "STARTING WI‑FI ACCESS POINT"

step "Enabling IPv4 forwarding (runtime)"
sudo sysctl -w net.ipv4.ip_forward=1

step "Ensuring NAT is configured"
sudo iptables -t nat -C POSTROUTING -o "$ethernet_id" -j MASQUERADE 2>/dev/null || {
  sudo iptables -t nat -A POSTROUTING -o "$ethernet_id" -j MASQUERADE
  info "NAT POSTROUTING rule added"
}

step "Reloading systemd services"
sudo systemctl daemon‑reexec

step "Restoring ipset rules (runtime)"
if [[ -f /etc/ipset.conf ]]; then
  sudo ipset restore < /etc/ipset.conf
  ok "ipsets restored from /etc/ipset.conf"
  sudo ipset list
else
  warn "No /etc/ipset.conf found — skipping restore"
fi

step "Restarting dnsmasq (standalone)"
sudo systemctl restart dnsmasq

step "Restarting hostapd"
sudo systemctl restart hostapd

step "Current iptables rules (filter and nat)"
sudo iptables -L -n -v --line-numbers
sudo iptables -t nat -L -n -v --line-numbers

step "Current ipsets"
sudo ipset list

sleep 2

# Confirm hostapd is running
if systemctl is-active --quiet hostapd; then
  ok "hostapd service is running"
else
  error "hostapd failed to start"
  sudo journalctl -u hostapd --no-pager -n 20
  exit 1
fi

step "Verifying IP address on $wireless_id"
ip addr show "$wireless_id" | grep "inet " || warn "$wireless_id has no IP assigned"

step "Connected stations on $wireless_id"
sudo iw dev "$wireless_id" station dump || info "No clients connected"

ok "Wi-Fi Access Point is up and operational"
