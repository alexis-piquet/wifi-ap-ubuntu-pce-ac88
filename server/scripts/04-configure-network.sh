#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../lib/log.sh"
. "$SCRIPT_DIR/../.env"

section "Configure network"

# Ensure the target directory exists for interface configs
step "Ensuring /etc/network/interfaces.d exists"
sudo mkdir -p /etc/network/interfaces.d

CONFIG_FILE="config/interfaces.d/$wireless_id"
TARGET_FILE="/etc/network/interfaces.d/$wireless_id"

if [[ ! -f "$CONFIG_FILE" ]]; then
  warn "Missing $CONFIG_FILE – generating fallback config"
  cat <<EOF | sudo tee "$TARGET_FILE" > /dev/null
auto $wireless_id
iface $wireless_id inet static
  address 10.0.0.1
  netmask 255.255.255.0
EOF
else
  step "Copying $CONFIG_FILE to $TARGET_FILE"
  sudo cp "$CONFIG_FILE" "$TARGET_FILE"
fi

step "Restarting network interface"

if systemctl list-units --type=service | grep -q '^networking.service'; then
  sudo systemctl restart networking
else
  warn "networking.service not found – falling back to ifdown/ifup"
  sudo ifdown "$wireless_id" || true
  sudo ifup "$wireless_id" || true
fi

ok "Static IP configured on $wireless_id"
