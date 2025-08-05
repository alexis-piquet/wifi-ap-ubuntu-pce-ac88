#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../lib/log.sh"

section "Enable service"

step "Copying config files"
sudo mkdir -p /etc/hostapd

if [[ ! -f "$SCRIPT_DIR/../config/hostapd.conf" ]]; then
  error "Missing file: config/hostapd.conf"
  exit 1
fi

if [[ ! -f "$SCRIPT_DIR/../config/hostapd.service" ]]; then
  error "Missing file: config/hostapd.service"
  exit 1
fi

sudo cp "$SCRIPT_DIR/../config/hostapd.conf" /etc/hostapd/hostapd.conf
sudo cp "$SCRIPT_DIR/../config/hostapd.service" /etc/systemd/system/hostapd.service

step "Enabling and starting hostapd"
sudo systemctl daemon-reload
sudo systemctl enable hostapd
sudo systemctl restart hostapd

ok "hostapd systemd service is running"
