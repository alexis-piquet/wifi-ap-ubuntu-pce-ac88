#!/usr/bin/env bash
set -euo pipefail

# Go to script directory
cd "$(dirname "$0")"

# Load logger
. lib/log.sh

section "WIFI ACCESS POINT - FULL INSTALLATION"

SCRIPTS=(
  "00-install-dependencies.sh"
  "01-check-env.sh"
  "02-install-firmware.sh"
  "03-compile-hostapd.sh"
  "04-configure-network.sh"
  "05-configure-dnsmasq.sh"
  "06-enable-nat.sh"
  "07-enable-services.sh"
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
