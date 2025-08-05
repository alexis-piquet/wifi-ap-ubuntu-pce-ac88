#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib/log.sh
. "$(dirname "$0")/lib/log.sh"

section "ENV CHECK"
step "Detecting interfaces via nmcli"

ethernet_id=$(nmcli dev status | awk '{print $1}' | grep -E '^en' | head -n1 || true)
wireless_id=$(nmcli dev status | awk '{print $1}' | grep -E '^wl' | head -n1 || true)

if [[ -z "${ethernet_id}" || -z "${wireless_id}" ]]; then
  error "Interfaces not found (ethernet='${ethernet_id:-}' wifi='${wireless_id:-}')."
  exit 1
fi

info  "Ethernet: ${BOLD}$ethernet_id${NC}"
info  "Wireless: ${BOLD}$wireless_id${NC}"

printf "export ethernet_id=%s\nexport wireless_id=%s\n" "$ethernet_id" "$wireless_id" > .env
ok "Environment written to .env"
