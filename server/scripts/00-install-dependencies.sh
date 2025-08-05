#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../lib/log.sh"

step "Checking required system packages"

REQUIRED_PACKAGES=(
  network-manager
  iptables
  rfkill
  curl
  wget
  git
)

MISSING_PACKAGES=()

for pkg in "${REQUIRED_PACKAGES[@]}"; do
  if ! dpkg -s "$pkg" &>/dev/null; then
    MISSING_PACKAGES+=("$pkg")
  fi
done

if (( ${#MISSING_PACKAGES[@]} > 0 )); then
  warn "Missing packages: ${MISSING_PACKAGES[*]}"
  step "Installing missing packages..."
  sudo apt update
  sudo apt install -y "${MISSING_PACKAGES[@]}"
  ok "All required packages installed"
else
  ok "All required packages already installed"
fi