#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../lib/log.sh"
. "$SCRIPT_DIR/../.env"

section Test and Debug"

step "IP addresses"
ip a

step "DHCP check"
nmcli dev show "$wireless_id" | grep IP4 || warn "No DHCP address?"

step "Connected clients"
sudo iw dev "$wireless_id" station dump || info "No clients connected"

step "iptables NAT table"
sudo iptables -t nat -L -n -v

ok "Diagnostics completed"
