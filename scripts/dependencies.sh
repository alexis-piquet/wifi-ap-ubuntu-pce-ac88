#!/usr/bin/env bash
set -euo pipefail

CURRENT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_PATH/../lib/utils.sh"

export LOG_NAMESPACE="[SCRIPTS][DEPENDENCIES]"
source_as "$CURRENT_PATH/../lib/log.sh" "LOGGER"

init() {
  LOGGER section "Trying to installrequired dependencies"

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
  LOGGER warn "Missing packages: ${MISSING_PACKAGES[*]}"
  LOGGER step "Installing missing packages..."
  sudo apt update
  sudo apt install -y "${MISSING_PACKAGES[@]}"
  LOGGER ok "All required packages installed"
else
  LOGGER ok "All required packages already installed"
fi
}