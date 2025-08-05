#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../lib/log.sh"
. "$SCRIPT_DIR/../.env"

section "CONFIGURE STATIC IP"

step "Copying interfaces file for $wireless_id"
sudo cp config/interfaces /etc/network/interfaces.d/$wireless_id

step "Restarting networking service"
sudo systemctl restart networking

ok "Static IP configured on $wireless_id"
