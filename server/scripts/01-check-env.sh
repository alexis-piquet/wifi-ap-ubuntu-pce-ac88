#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../lib/log.sh"

section "ENV CHECK"
step "Detecting interfaces via nmcli"

ethernet_id=$(nmcli dev status | awk '{print $1}' | grep -E '^en' | head -n1 || true)
wireless_id=$(nmcli dev status | awk '{print $1}' | grep -E '^wl' | head -n1 || true)

if [[ -z "${ethernet_id}" ]]; then
  error "Ethernet interface not found"
  exit 1
fi

if [[ -z "${wireless_id}" ]]; then
  warn "Wi-Fi interface not found (yet) — this may be expected before firmware setup"
fi

info  "Ethernet: ${BOLD}$ethernet_id${NC}"
info  "Wireless: ${BOLD}$wireless_id${NC}"

printf "export ethernet_id=%s\nexport wireless_id=%s\n" "$ethernet_id" "$wireless_id" > .env
ok "Environment written to .env"
