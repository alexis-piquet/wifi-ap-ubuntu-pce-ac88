#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../lib/log.sh"

section "Configure dnsmasq"

step "Creating dnsmasq.d directory"
sudo mkdir -p /etc/NetworkManager/dnsmasq.d

step "Copying dnsmasq.conf"
sudo cp config/dnsmasq.conf /etc/NetworkManager/dnsmasq.d/

step "Editing NetworkManager config"
echo "[main]" | sudo tee /etc/NetworkManager/NetworkManager.conf
echo "dns=dnsmasq" | sudo tee -a /etc/NetworkManager/NetworkManager.conf

ok "dnsmasq configured"
