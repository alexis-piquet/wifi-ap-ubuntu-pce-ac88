#!/usr/bin/env bash
set -euo pipefail

CURRENT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$CURRENT_PATH/.."

source "$ROOT_DIR/lib/utils.sh"
source_as "$ROOT_DIR/lib/logger.sh" "LOGGER"

_load_env() {
  local env_file="$ROOT_DIR/.env"
  if [[ ! -f "$env_file" ]]; then
    LOGGER error "Missing .env file – run 010_env.sh first"
    exit 1
  fi
  # shellcheck source=/dev/null
  source "$env_file"

  : "${NET_MODE:=router}"     # router | bridge
  : "${WIRELESS_IF:=}"
  : "${BRIDGE_IF:=br0}"
}

_hostapd_unit_present() {
  systemctl cat hostapd >/dev/null 2>&1
}

_install_or_fix_hostapd_unit() {
  local src="$ROOT_DIR/config/services/hostapd.service"
  local etc_unit="/etc/systemd/system/hostapd.service"

  # Unmask if masked vers /dev/null
  if systemctl is-enabled hostapd 2>&1 | grep -q masked \
    || { [ -L "$etc_unit" ] && [[ "$(readlink -f "$etc_unit")" == "/dev/null" ]]; }; then
    LOGGER warn "hostapd.service is masked — unmasking"
    sudo systemctl stop hostapd 2>/dev/null || true
    sudo systemctl disable hostapd 2>/dev/null || true
    sudo systemctl unmask hostapd || true
    sudo rm -f "$etc_unit" || true
  fi

  # Install our unit if none is provided by the system
  if ! _hostapd_unit_present; then
    if [[ -f "$src" ]]; then
      LOGGER step "Installing custom hostapd.service"
      sudo install -m 0644 -T "$src" "$etc_unit"
    else
      LOGGER error "No hostapd systemd unit found and no custom unit at $src"
      exit 1
    fi
  fi

  # Point ExecStart to the correct binary if you manage the unit in /etc
  if [[ -f "$etc_unit" ]]; then
    local bin_path
    bin_path="$(command -v hostapd || echo /usr/local/sbin/hostapd)"
    sudo sed -i "s|^ExecStart=.*hostapd .*|ExecStart=${bin_path} -B /etc/hostapd/hostapd.conf|" "$etc_unit" || true
  fi

  sudo systemctl daemon-reload
}

_enable_start_dnsmasq_router() {
  # dnsmasq is only needed in router mode
  LOGGER step "Enabling and restarting dnsmasq (router mode)"
  sudo systemctl enable dnsmasq >/dev/null 2>&1 || true

  # Quick config test (security)
  if ! sudo dnsmasq --test --conf-file=/etc/dnsmasq.conf --conf-dir=/etc/dnsmasq.d; then
    LOGGER error "dnsmasq --test failed (check /etc/dnsmasq.d)"
    exit 1
  fi

  if ! sudo systemctl restart dnsmasq; then
    LOGGER error "Failed to start dnsmasq. Recent logs:"
    sudo journalctl -u dnsmasq -n 80 --no-pager || true
    exit 1
  fi
  LOGGER ok "dnsmasq is running"
}

_enable_start_hostapd() {
  LOGGER step "Enabling and starting hostapd"
  sudo systemctl enable hostapd >/dev/null 2>&1 || true
  if ! sudo systemctl restart hostapd; then
    LOGGER error "Failed to start hostapd. Recent logs:"
    sudo journalctl -u hostapd -n 120 --no-pager || true
    exit 1
  fi
  sleep 1
  systemctl --no-pager --full status hostapd | sed -n '1,20p' || true
  LOGGER ok "hostapd is running"
}

_start_ipset_restore_if_present() {
  if systemctl cat ipset-restore.service >/dev/null 2>&1; then
    LOGGER step "Ensuring ipset-restore.service is enabled"
    sudo systemctl enable ipset-restore.service >/dev/null 2>&1 || true
    sudo systemctl start ipset-restore.service  >/dev/null 2>&1 || true
  fi
}

_warn_if_missing_bits() {
  # Visual aids if key elements are missing
  if [[ "$NET_MODE" == "router" ]]; then
    if [[ -z "${WIRELESS_IF:-}" ]]; then
      LOGGER warn "WIRELESS_IF is empty — dnsmasq/hostapd may not bind correctly."
    fi
    if ! ip -4 addr show dev "${WIRELESS_IF:-dummy0}" | grep -q " ${AP_IP:-10.0.0.1}/"; then
      LOGGER warn "AP IP not found on ${WIRELESS_IF:-<unknown>} (030_network.sh should have set it)."
    fi
  fi
}


init_services() {
  _load_env
  _install_or_fix_hostapd_unit
  _warn_if_missing_bits

  case "$NET_MODE" in
    router)
      _enable_start_dnsmasq_router
      _start_ipset_restore_if_present
      _enable_start_hostapd
      ;;
    bridge)
      LOGGER info "NET_MODE=bridge → no dnsmasq/NAT; starting hostapd only"
      _enable_start_hostapd
      ;;
    *)
      LOGGER error "Unknown NET_MODE: $NET_MODE"
      exit 1
      ;;
  esac

  LOGGER ok "Services are up (mode: ${NET_MODE})"
}
