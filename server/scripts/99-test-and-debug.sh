#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../lib/log.sh"
. "$SCRIPT_DIR/../.env"

section "Test and Debug"

step "IP addresses"
ip a

step "DHCP check"
nmcli dev show "$wireless_id" | grep IP4 || warn "No DHCP address?"

step "Connected clients"
sudo iw dev "$wireless_id" station dump || info "No clients connected"

step "iptables NAT table"
sudo iptables -t nat -L -n -v

step "Testing ipsets"
sudo ipset list whitelist | head
sudo ipset list allow_all | head

info "Testing DNS resolution (should be allowed):"
dig example.com @127.0.0.1

info "Testing DNS resolution (should be blocked):"
dig facebook.com @127.0.0.1

ok "Diagnostics completed"
