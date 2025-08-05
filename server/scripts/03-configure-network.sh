#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/lib/log.sh"
. .env

section "CONFIGURE STATIC IP"

step "Copying interfaces file for $wireless_id"
sudo cp config/interfaces /etc/network/interfaces.d/$wireless_id

step "Restarting networking service"
sudo systemctl restart networking

ok "Static IP configured on $wireless_id"
