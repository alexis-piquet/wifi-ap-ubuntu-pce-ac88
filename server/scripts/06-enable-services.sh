#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../lib/log.sh"

section "ENABLE HOSTAPD SERVICE"

step "Copying config files"
sudo cp config/hostapd.conf /etc/hostapd/hostapd.conf
sudo cp config/hostapd.service /etc/systemd/system/hostapd.service

step "Enabling and starting hostapd"
sudo systemctl daemon-reload
sudo systemctl enable hostapd
sudo systemctl restart hostapd

ok "hostapd systemd service is running"
