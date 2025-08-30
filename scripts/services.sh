#!/usr/bin/env bash
set -euo pipefail

CURRENT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_PATH/../lib/utils.sh"
source_as "$CURRENT_PATH/../lib/logger.sh" "LOGGER"

init_services() {
  LOGGER info "Setting up NAT and IP forwarding"

  if [[ -f "$CURRENT_PATH/../.env" ]]; then
    source "$CURRENT_PATH/../.env"
  else
    LOGGER error "Missing .env file – cannot proceed"
    exit 1
  fi

  sudo mkdir -p /etc/hostapd

  [[ -f "$CURRENT_PATH/../config/hostapd.conf"    ]] || { LOGGER error "Missing file: config/hostapd.conf"    ; exit 1; }
  [[ -f "$CURRENT_PATH/../config/hostapd.service" ]] || { LOGGER error "Missing file: config/hostapd.service" ; exit 1; }

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

  SRC_UNIT="$CURRENT_PATH/../config/hostapd.service"
  DST_UNIT="/etc/systemd/system/hostapd.service"

  if systemctl is-enabled hostapd 2>&1 | grep -q masked \
    || { [ -L "$DST_UNIT" ] && [[ "$(readlink -f "$DST_UNIT")" == "/dev/null" ]]; }; then
    LOGGER warn "hostapd.service is masked — unmasking & replacing unit"
    sudo systemctl stop hostapd 2>/dev/null || true
    sudo systemctl disable hostapd 2>/dev/null || true
    sudo systemctl unmask hostapd || true
    sudo rm -f "$DST_UNIT" || true
  fi

  sudo install -m 0644 -T "$SRC_UNIT" "$DST_UNIT"

  HOSTAPD_BIN="$(command -v hostapd || echo /usr/local/sbin/hostapd)"
  sudo sed -i "s|^ExecStart=.*hostapd.*|ExecStart=$HOSTAPD_BIN -B /etc/hostapd/hostapd.conf|" "$DST_UNIT"

  LOGGER step "Enabling and starting hostapd"
  sudo systemctl daemon-reload
  sudo systemctl enable --now hostapd

  LOGGER ok "hostapd systemd service is running"
}