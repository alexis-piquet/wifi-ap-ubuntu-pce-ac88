#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../lib/log.sh"
. "$SCRIPT_DIR/../.env"

section "Configure network"

# Ensure the target directory exists for interface configs
step "Ensuring /etc/network/interfaces.d exists"
sudo mkdir -p /etc/network/interfaces.d

# Copy the main 'interfaces' file if it exists in the config directory
if [[ -f config/interfaces ]]; then
  step "Copying main interfaces config"
  sudo cp config/interfaces /etc/network/interfaces
fi

# Copy a specific interface config if it exists, fallback if missing
interface_conf="config/interfaces.d/$wireless_id"
if [[ -f "$interface_conf" ]]; then
  step "Copying interface config for $wireless_id"
  sudo cp "$interface_conf" /etc/network/interfaces.d/"$wireless_id"
else
  warn "Missing config/interfaces.d/$wireless_id — generating fallback config"
  echo -e "auto $wireless_id\niface $wireless_id inet static\n  address 192.168.10.1\n  netmask 255.255.255.0" | sudo tee /etc/network/interfaces.d/"$wireless_id" > /dev/null
fi

# Restart networking to apply changes
step "Restarting networking service"
sudo systemctl restart networking

ok "Static IP configured on $wireless_id"
