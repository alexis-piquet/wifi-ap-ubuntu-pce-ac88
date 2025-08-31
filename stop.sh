#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$ROOT_DIR/lib/utils.sh"
export LOG_NAMESPACE="[STOP]"
source_as "$ROOT_DIR/lib/logger.sh" "LOGGER"

_load_env() {
  local env_file="$ROOT_DIR/.env"
  if [[ -f "$env_file" ]]; then
    # shellcheck source=/dev/null
    source "$env_file"
  fi
  : "${NET_MODE:=router}"
  : "${WIRELESS_IF:=}"
}

_stop_hostapd() {
  LOGGER step "Stopping hostapd"
  if systemctl list-unit-files | grep -q '^hostapd\.service'; then
    sudo systemctl stop hostapd || true
  fi
}

_stop_dnsmasq_if_router() {
  [[ "$NET_MODE" == "router" ]] || return 0
  LOGGER step "Stopping dnsmasq"
  if systemctl list-unit-files | grep -q '^dnsmasq\.service'; then
    sudo systemctl stop dnsmasq || true
  fi
}

_optionally_drop_runtime_forwarding() {
  # We **do not** touch persistent sysctl.d or saved iptables.
  # This only flips the *runtime* bit if desired.
  if [[ "${DISABLE_FORWARD_RUNTIME:-0}" == "1" ]]; then
    LOGGER step "Disabling IPv4 forwarding (runtime)"
    sudo sysctl -w net.ipv4.ip_forward=0 >/dev/null || true
  fi
}

_down_wifi_if_requested() {
  if [[ -n "${WIRELESS_IF:-}" && "${DOWN_WIFI_IF:-0}" == "1" ]]; then
    LOGGER step "Bringing ${WIRELESS_IF} down (requested)"
    sudo ip link set "$WIRELESS_IF" down || true
  fi
}

_summary() {
  LOGGER step "Services status"
  systemctl is-active hostapd  && LOGGER info "hostapd: active"  || LOGGER info "hostapd: inactive"
  systemctl is-active dnsmasq && LOGGER info "dnsmasq: active"   || LOGGER info "dnsmasq: inactive"
  LOGGER ok "Stopped"
}

main() {
  LOGGER section "STOPPING WI-FI ACCESS POINT"
  _load_env
  _stop_hostapd
  _stop_dnsmasq_if_router
  _optionally_drop_runtime_forwarding
  _down_wifi_if_requested
  _summary
}
main "$@"
