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

  : "${NET_MODE:=router}"          # router | bridge
  : "${ETHERNET_IF:=}"
  : "${WIRELESS_IF:=}"
  : "${BRIDGE_IF:=br0}"
  : "${AP_IP:=${AP_CIDR%/*}}"
}

_cmd_ok() { command -v "$1" >/dev/null 2>&1; }

_show_header() {
  LOGGER step "$1"
}

_show_cmd() {
  local desc="$1"; shift
  LOGGER info "$desc"
  # shellcheck disable=SC2068
  "$@" || true
}

_check_interfaces() {
  _show_header "Interfaces (ip -br addr / link)"
  ip -br addr || true
  ip -br link || true

  if [[ -n "${WIRELESS_IF:-}" ]] && ip link show "$WIRELESS_IF" &>/dev/null; then
    LOGGER ok "Wireless IF detected: $WIRELESS_IF"
  else
    LOGGER warn "WIRELESS_IF not detected or empty"
  fi

  if [[ -n "${ETHERNET_IF:-}" ]] && ip link show "$ETHERNET_IF" &>/dev/null; then
    LOGGER ok "Ethernet IF detected: $ETHERNET_IF"
  else
    LOGGER warn "ETHERNET_IF not detected or empty"
  fi

  if [[ "$NET_MODE" == "bridge" ]]; then
    if ip link show "$BRIDGE_IF" &>/dev/null; then
      LOGGER ok "Bridge present: $BRIDGE_IF"
    else
      LOGGER error "Bridge expected but not found: $BRIDGE_IF"
    fi
  fi
}

_check_wifi_stack() {
  _show_header "Wi-Fi stack (rfkill / iw / dmesg brcmfmac)"
  if _cmd_ok rfkill; then
    rfkill list || true
  fi
  if _cmd_ok iw; then
    iw reg get || true
    iw dev || true
    if [[ -n "${WIRELESS_IF:-}" ]]; then
      iw dev "$WIRELESS_IF" info || true
      iw dev "$WIRELESS_IF" link || true
      sudo iw dev "$WIRELESS_IF" station dump || true
    fi
  fi
  dmesg | grep -i -E 'brcmfmac|brcm' | tail -n 50 || true
}

_check_routes() {
  _show_header "Routing"
  ip route || true
}

_check_hostapd() {
  _show_header "hostapd status"
  if systemctl list-unit-files | grep -q '^hostapd\.service'; then
    systemctl --no-pager --full status hostapd | sed -n '1,25p' || true
    LOGGER info "hostapd version: $(hostapd -v 2>/dev/null || echo 'unknown')"
    LOGGER info "Last logs:"
    sudo journalctl -u hostapd -n 50 --no-pager || true
  else
    LOGGER warn "hostapd.service not found"
  fi

  if [[ -f /etc/hostapd/hostapd.conf ]]; then
    LOGGER ok "/etc/hostapd/hostapd.conf present"
    sudo head -n 20 /etc/hostapd/hostapd.conf || true
  else
    LOGGER error "/etc/hostapd/hostapd.conf missing"
  fi
}

_check_dnsmasq_router() {
  [[ "$NET_MODE" == "router" ]] || return 0

  _show_header "dnsmasq (router mode)"
  if systemctl list-unit-files | grep -q '^dnsmasq\.service'; then
    if ! sudo dnsmasq --test --conf-file=/etc/dnsmasq.conf --conf-dir=/etc/dnsmasq.d; then
      LOGGER error "dnsmasq --test failed"
    else
      LOGGER ok "dnsmasq config test passed"
    fi
    systemctl --no-pager --full status dnsmasq | sed -n '1,20p' || true
    sudo journalctl -u dnsmasq -n 50 --no-pager || true
  else
    LOGGER warn "dnsmasq.service not found (router mode expects it)"
  fi

  _show_header "dnsmasq binds (ss :53)"
  sudo ss -ltnp '( sport = :53 )' || true

  if [[ -n "${WIRELESS_IF:-}" ]]; then
    local bound
    bound="$(ip -4 addr show dev "$WIRELESS_IF" | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)"
    if [[ -n "$bound" ]]; then
      LOGGER ok "AP_IP on ${WIRELESS_IF}: $bound"
      if _cmd_ok dig; then
        _show_cmd "DNS test via dnsmasq (@$bound): dig example.com +short" dig @"$bound" example.com +short
      elif _cmd_ok nslookup; then
        _show_cmd "DNS test via dnsmasq (@$bound): nslookup example.com $bound" nslookup example.com "$bound"
      else
        LOGGER warn "Neither dig nor nslookup installed; skipping DNS query test"
      fi
      if [[ -f /var/lib/misc/dnsmasq.leases ]]; then
        _show_header "dnsmasq leases"
        sudo cat /var/lib/misc/dnsmasq.leases || true
      fi
    else
      LOGGER warn "No IPv4 on ${WIRELESS_IF}; dnsmasq binding may fail"
    fi
  fi
}

_check_nat_router() {
  [[ "$NET_MODE" == "router" ]] || return 0

  _show_header "NAT / iptables"
  sudo iptables -t nat -S | sed -n '1,80p' || true
  sudo iptables -S FORWARD | sed -n '1,80p' || true

  if sudo iptables -t nat -C POSTROUTING -o "${ETHERNET_IF:-dummy0}" -j MASQUERADE 2>/dev/null; then
    LOGGER ok "MASQUERADE on ${ETHERNET_IF} present"
  else
    LOGGER error "MASQUERADE on ${ETHERNET_IF} missing"
  fi

  if sudo iptables -C FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null; then
    LOGGER ok "FORWARD rule ESTABLISHED,RELATED present"
  else
    LOGGER warn "FORWARD rule ESTABLISHED,RELATED missing"
  fi
}

_check_allowlist_router() {
  [[ "$NET_MODE" == "router" ]] || return 0

  _show_header "Allowlist (ipset)"
  if sudo ipset list whitelist &>/dev/null; then
    sudo ipset list whitelist | head -n 20 || true
    LOGGER ok "ipset 'whitelist' exists"
  else
    LOGGER warn "ipset 'whitelist' missing"
  fi

  if sudo ipset list allow_all &>/dev/null; then
    sudo ipset list allow_all | head -n 20 || true
    LOGGER ok "ipset 'allow_all' exists"
  else
    LOGGER warn "ipset 'allow_all' missing"
  fi

  _show_header "iptables chain WIFI_ALLOWLIST (if configured)"
  sudo iptables -S WIFI_ALLOWLIST 2>/dev/null || LOGGER info "Chain WIFI_ALLOWLIST not found (ok if allowlist disabled)"
}

init_doctor() {
  LOGGER info "Doctor / Diagnostics (mode-aware)"
  _load_env

  LOGGER info "NET_MODE=${NET_MODE}  ETH=${ETHERNET_IF:-<none>}  WIFI=${WIRELESS_IF:-<none>}  BR=${BRIDGE_IF}  AP_IP=${AP_IP:-<none>}"

  _check_interfaces
  _check_wifi_stack
  _check_routes
  _check_hostapd
  _check_dnsmasq_router
  _check_nat_router
  _check_allowlist_router

  LOGGER ok "Diagnostics completed"
}
