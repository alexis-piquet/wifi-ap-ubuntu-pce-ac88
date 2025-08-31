#!/usr/bin/env bash
set -euo pipefail

CURRENT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$CURRENT_PATH"

source    "./lib/utils.sh"

export LOG_NAMESPACE="[START]"

source_as "./lib/logger.sh" "LOGGER"

_load_env() {
  local env_file="$ROOT_DIR/.env"
  if [[ ! -f "$env_file" ]]; then
    LOGGER error "Missing .env — run ./init.sh first"
    exit 1
  fi
  # shellcheck source=/dev/null
  source "$env_file"

  : "${NET_MODE:=router}"             # router | bridge
  : "${ETHERNET_IF:?Set ETHERNET_IF in .env}"
  : "${WIRELESS_IF:?Set WIRELESS_IF in .env}"
  : "${BRIDGE_IF:=br0}"
  : "${AP_CIDR:=10.0.0.1/24}"
  : "${AP_IP:=${AP_CIDR%/*}}"
  : "${WIRELESS_COUNTRY:=FR}"
}

_rfkill_and_regdomain() {
  if command -v rfkill >/dev/null 2>&1; then
    LOGGER step "Unblocking Wi-Fi (rfkill)"
    sudo rfkill unblock wifi || true
  fi
  if command -v iw >/dev/null 2>&1; then
    LOGGER info "Setting reg domain: ${WIRELESS_COUNTRY}"
    sudo iw reg set "${WIRELESS_COUNTRY}" || true
  fi
}

_assign_ap_ip_if_needed() {
  [[ "$NET_MODE" == "router" ]] || return 0
  LOGGER step "Ensuring AP IP (${AP_CIDR}) on ${WIRELESS_IF}"
  sudo ip link set "$WIRELESS_IF" up || true
  if ! ip -4 addr show dev "$WIRELESS_IF" | grep -q " ${AP_IP}/"; then
    sudo ip addr replace "$AP_CIDR" dev "$WIRELESS_IF"
  fi
  LOGGER info "Interface summary: $(ip -br addr show "$WIRELESS_IF" | awk '{$1=$1;print}')"
}

_enable_forward_runtime() {
  [[ "$NET_MODE" == "router" ]] || return 0
  LOGGER step "Enabling IPv4 forwarding (runtime)"
  sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null
}

_ensure_nat_and_forward_rules() {
  [[ "$NET_MODE" == "router" ]] || return 0
  LOGGER step "Ensuring NAT/forwarding rules (idempotent)"

  # ESTABLISHED,RELATED
  sudo iptables -C FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null \
    || sudo iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

  # Prefer allowlist chain if present; else generic ACCEPT WiFi->Eth
  if sudo iptables -S WIFI_ALLOWLIST &>/dev/null; then
    sudo iptables -C FORWARD -i "$WIRELESS_IF" -o "$ETHERNET_IF" -j WIFI_ALLOWLIST 2>/dev/null \
      || sudo iptables -I FORWARD 1 -i "$WIRELESS_IF" -o "$ETHERNET_IF" -j WIFI_ALLOWLIST
  else
    sudo iptables -C FORWARD -i "$WIRELESS_IF" -o "$ETHERNET_IF" -j ACCEPT 2>/dev/null \
      || sudo iptables -A FORWARD -i "$WIRELESS_IF" -o "$ETHERNET_IF" -j ACCEPT
  fi

  # MASQUERADE on WAN
  sudo iptables -t nat -C POSTROUTING -o "$ETHERNET_IF" -j MASQUERADE 2>/dev/null \
    || sudo iptables -t nat -A POSTROUTING -o "$ETHERNET_IF" -j MASQUERADE
}

_start_dnsmasq_if_router() {
  [[ "$NET_MODE" == "router" ]] || return 0
  if systemctl list-unit-files | grep -q '^dnsmasq\.service'; then
    LOGGER step "Starting dnsmasq"
    # quick sanity
    sudo dnsmasq --test --conf-file=/etc/dnsmasq.conf --conf-dir=/etc/dnsmasq.d || {
      LOGGER error "dnsmasq --test failed"
      exit 1
    }
    sudo systemctl restart dnsmasq
    LOGGER ok "dnsmasq running"
  else
    LOGGER warn "dnsmasq.service not installed (expected in router mode)"
  fi
}

_start_ipset_restore_if_present() {
  if systemctl list-unit-files | grep -q '^ipset-restore\.service'; then
    LOGGER step "Starting ipset-restore (best-effort)"
    sudo systemctl start ipset-restore.service || true
  fi
}

_start_hostapd() {
  LOGGER step "Starting hostapd"
  if [[ -f /etc/hostapd/hostapd.conf ]]; then
    sudo hostapd -t /etc/hostapd/hostapd.conf || {
      LOGGER error "hostapd config test failed"
      exit 1
    }
  fi
  sudo systemctl restart hostapd || {
    LOGGER error "hostapd failed to start"; sudo journalctl -u hostapd -n 120 --no-pager || true; exit 1;
  }
  sleep 1
  systemctl --no-pager --full status hostapd | sed -n '1,20p' || true
  LOGGER ok "hostapd running"
}

_summary() {
  LOGGER step "Quick status"
  ip -br addr show "$WIRELESS_IF" || true
  sudo ss -ltnp '( sport = :53 )' 2>/dev/null || true
  if command -v iw >/dev/null 2>&1; then
    sudo iw dev "$WIRELESS_IF" station dump || true
  fi
  LOGGER ok "Access point is up"
}

main() {
  LOGGER section "STARTING WI-FI ACCESS POINT"
  _load_env
  _rfkill_and_regdomain
  _assign_ap_ip_if_needed
  _enable_forward_runtime
  _ensure_nat_and_forward_rules
  _start_dnsmasq_if_router
  _start_ipset_restore_if_present
  _start_hostapd
  _summary
}
main "$@"
