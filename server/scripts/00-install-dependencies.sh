#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../lib/log.sh"

step "Install dependencies"

REQUIRED_PACKAGES=(
  build-essential
  crda
  libssl-dev
  libnl-3-dev
  libnl-genl-3-dev
  libnl-route-3-dev
  libnfnetlink-dev
  pkg-config
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
