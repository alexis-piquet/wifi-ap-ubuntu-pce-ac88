#!/usr/bin/env bash
set -euo pipefail

# Go to script directory
cd "$(dirname "$0")"

# Load logger
. lib/log.sh

section "WIFI ACCESS POINT - FULL INSTALLATION"

SCRIPTS=(
  "00-check-env.sh"
  "01-install-firmware.sh"
  "02-compile-hostapd.sh"
  "03-configure-network.sh"
  "04-configure-dnsmasq.sh"
  "05-enable-nat.sh"
  "06-enable-services.sh"
  "99-test-and-debug.sh"
)

for script in "${SCRIPTS[@]}"; do
  path="./scripts/$script"
  if [[ -x "$path" ]]; then
    step "Running $script"
    "$path"
  else
    warn "Script not found or not executable: $script"
  fi
done

ok "Installation complete. You can now run: ./start.sh"
