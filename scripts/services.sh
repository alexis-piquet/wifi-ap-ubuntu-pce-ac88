#!/usr/bin/env bash
set -euo pipefail

CURRENT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_PATH/../lib/utils.sh"

export LOG_NAMESPACE="[SCRIPTS][SERVICES]"
source_as "$CURRENT_PATH/../lib/logger.sh" "LOGGER"

init() {
  LOGGER info "Setting up NAT and IP forwarding"
  if [[ -f "$CURRENT_PATH/../.env" ]]; then
    source "$CURRENT_PATH/../.env"
  else
    LOGGER error "Missing .env file – cannot proceed"
    exit 1
  fi

  sudo mkdir -p /etc/hostapd

  if [[ ! -f "$CURRENT_PATH/../config/hostapd.conf" ]]; then
    LOGGER error "Missing file: config/hostapd.conf"
    exit 1
  fi

  if [[ ! -f "$CURRENT_PATH/../config/hostapd.service" ]]; then
    LOGGER error "Missing file: config/hostapd.service"
    exit 1
  fi

  sudo cp "$CURRENT_PATH/../config/hostapd.conf" /etc/hostapd/hostapd.conf

  if grep -q '^interface=' /etc/hostapd/hostapd.conf; then
    sudo sed -i "s/^interface=.*/interface=$wireless_id/" /etc/hostapd/hostapd.conf
  else
    echo "interface=$wireless_id" | sudo tee -a /etc/hostapd/hostapd.conf >/dev/null
  fi

  if [[ -n "${bridge_id:-}" ]]; then
    if grep -q '^bridge=' /etc/hostapd/hostapd.conf; then
      sudo sed -i "s/^bridge=.*/bridge=$bridge_id/" /etc/hostapd/hostapd.conf
    else
      echo "bridge=$bridge_id" | sudo tee -a /etc/hostapd/hostapd.conf >/dev/null
    fi
  fi

  # Copier l'unité systemd
  sudo cp "$CURRENT_PATH/../config/hostapd.service" /etc/systemd/system/hostapd.service

  LOGGER step "Enabling and starting hostapd"
  sudo systemctl daemon-reload
  sudo systemctl enable hostapd
  sudo systemctl restart hostapd

  LOGGER ok "hostapd systemd service is running"
}