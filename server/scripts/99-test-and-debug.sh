#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/lib/log.sh"
. .env

section "DIAGNOSTIC QUICK TESTS"

step "IP addresses"
ip a

step "DHCP check"
nmcli dev show "$wireless_id" | grep IP4 || warn "No DHCP address?"

step "Connected clients"
sudo iw dev "$wireless_id" station dump || info "No clients connected"

step "iptables NAT table"
sudo iptables -t nat -L -n -v

ok "Diagnostics completed"
