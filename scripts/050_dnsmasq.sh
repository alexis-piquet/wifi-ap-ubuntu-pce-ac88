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

  : "${NET_MODE:=router}"
  : "${WIRELESS_IF:=}"              # may still be empty if firmware not ready
  : "${WIRELESS_INTERFACE:=}"       # accept either name
  : "${AP_CIDR:=}"                  # e.g. 10.0.0.1/24
  : "${AP_IP:=}"
  : "${DHCP_START:=}"
  : "${DHCP_END:=}"

  # Normalize interface names (support both)
  if [[ -z "${WIRELESS_INTERFACE:-}" && -n "${WIRELESS_IF:-}" ]]; then
    WIRELESS_INTERFACE="$WIRELESS_IF"
  fi
  if [[ -z "${WIRELESS_IF:-}" && -n "${WIRELESS_INTERFACE:-}" ]]; then
    WIRELESS_IF="$WIRELESS_INTERFACE"
  fi

  # Compute AP_IP if needed
  if [[ -z "${AP_IP:-}" ]]; then
    if [[ -n "${AP_CIDR:-}" ]]; then
      AP_IP="${AP_CIDR%/*}"
    else
      AP_IP="10.0.0.1"
    fi
  fi

  # Compute DHCP range if needed (assume /24)
  if [[ -z "${DHCP_START:-}" || -z "${DHCP_END:-}" ]]; then
    local ap_net
    ap_net="$(printf "%s\n" "$AP_IP" | awk -F. '{printf "%d.%d.%d",$1,$2,$3}')"
    DHCP_START="${ap_net}.10"
    DHCP_END="${ap_net}.200"
  fi

  if [[ "${NET_MODE}" != "router" ]]; then
    LOGGER info "NET_MODE=${NET_MODE} → dnsmasq not required (skipping)."
    exit 0
  fi

  if [[ -z "${WIRELESS_INTERFACE:-}" ]]; then
    LOGGER warn "WIRELESS_IF/ WIRELESS_INTERFACE is empty — dnsmasq may fail to bind; continuing anyway."
  fi

  # Export everything templates may reference
  export WIRELESS_INTERFACE WIRELESS_IF AP_IP DHCP_START DHCP_END
}

_purge_legacy_nm_snippet() {
  # If you previously experimented with NM’s internal dnsmasq, its snippet may linger.
  local nm_snip="/etc/NetworkManager/dnsmasq.d/dnsmasq.conf"
  if [[ -f "$nm_snip" ]]; then
    LOGGER warn "Removing legacy NetworkManager dnsmasq snippet: $nm_snip"
    sudo rm -f "$nm_snip"
  fi
}

_render_wifi_ap_conf() {
  local tpl="$ROOT_DIR/config/dnsmasq/wifi-ap.conf"
  local dst="/etc/dnsmasq.d/wifi-ap.conf"

  LOGGER step "Rendering dnsmasq AP config → $dst"
  sudo install -d -m 0755 /etc/dnsmasq.d

  if [[ -f "$tpl" ]]; then
    if command -v envsubst >/dev/null 2>&1; then
      # Replace both ${WIRELESS_INTERFACE} and ${WIRELESS_IF}
      envsubst '$WIRELESS_INTERFACE$WIRELESS_IF$AP_IP$DHCP_START$DHCP_END' < "$tpl" \
        | sudo tee "$dst" >/dev/null
    else
      # Fallback: sed both variants
      sudo sed \
        -e "s|\${WIRELESS_INTERFACE}|${WIRELESS_INTERFACE:-}|g" \
        -e "s|\${WIRELESS_IF}|${WIRELESS_IF:-}|g" \
        -e "s|\${AP_IP}|${AP_IP:-}|g" \
        -e "s|\${DHCP_START}|${DHCP_START:-}|g" \
        -e "s|\${DHCP_END}|${DHCP_END:-}|g" \
        "$tpl" | sudo tee "$dst" >/dev/null
    fi
  else
    LOGGER warn "Missing $tpl — generating a minimal config"
    sudo tee "$dst" >/dev/null <<EOF
# listening only AP interface
interface=${WIRELESS_INTERFACE:-${WIRELESS_IF:-}}
bind-interfaces
listen-address=${AP_IP:-10.0.0.1}

# upstream DNS
no-resolv
server=1.1.1.1
server=1.0.0.1

# DHCP
dhcp-range=${DHCP_START:-10.0.0.10},${DHCP_END:-10.0.0.200},255.255.255.0,12h
dhcp-option=option:router,${AP_IP:-10.0.0.1}
dhcp-option=option:dns-server,${AP_IP:-10.0.0.1}
EOF
  fi

  # Hard-fail if any placeholder remains
  if sudo grep -q '\${[A-Za-z_][A-Za-z0-9_]*}' "$dst"; then
    LOGGER error "Unexpanded variable(s) found in $dst:"
    sudo awk '/\$\{[A-Za-z_][A-Za-z0-9_]*\}/ {print "  " $0}' "$dst" || true
    exit 1
  fi

  sudo chmod 0644 "$dst"
  LOGGER ok "wifi-ap.conf ready"
}

_sanitize_bind_options() {
  LOGGER step "Sanitizing dnsmasq bind options (remove bind-dynamic / stray bind-interfaces)"

  if [[ -f /etc/default/dnsmasq ]]; then
    sudo sed -i -E 's/(DNSMASQ_OPTS|OPTIONS)=.*$/DNSMASQ_OPTS=""/' /etc/default/dnsmasq 2>/dev/null || true
    sudo sed -i -E 's/--bind-(interfaces|dynamic)//g' /etc/default/dnsmasq || true
  fi

  sudo sed -i -E '/^\s*bind-(interfaces|dynamic)\s*$/d' /etc/dnsmasq.conf 2>/dev/null || true

  sudo find /etc/dnsmasq.d -maxdepth 1 -type f -name "*.conf" ! -name "wifi-ap.conf" -print0 \
    | xargs -0 -r sudo sed -i -E '/^\s*bind-(interfaces|dynamic)\s*$/d'

  sudo sed -i -E 's/^\s*bind-(interfaces|dynamic)\s*$/bind-interfaces/' /etc/dnsmasq.d/wifi-ap.conf
}

_check_ap_ip_presence() {
  local ifname="${WIRELESS_INTERFACE:-${WIRELESS_IF:-}}"
  if [[ -n "$ifname" ]]; then
    if ! ip -4 addr show dev "$ifname" | grep -q " ${AP_IP}/"; then
      LOGGER warn "AP_IP ${AP_IP} not present on ${ifname}. (030_network.sh should assign it in router mode)"
    fi
  fi
}

_test_and_restart() {
  LOGGER step "Config test (dnsmasq --test with conf-dir)"
  if ! sudo dnsmasq --test --conf-file=/etc/dnsmasq.conf --conf-dir=/etc/dnsmasq.d; then
    LOGGER error "dnsmasq --test failed"
    exit 1
  fi

  if sudo ss -ltnp '( sport = :53 )' 2>/dev/null | grep -q systemd-resolved; then
    LOGGER info "systemd-resolved owns :53; dnsmasq is bound to ${WIRELESS_INTERFACE:-${WIRELESS_IF:-<unset>}}:${AP_IP}."
  fi

  LOGGER step "Restarting dnsmasq service"
  if ! sudo systemctl restart dnsmasq; then
    LOGGER error "dnsmasq failed to restart. Last logs:"
    sudo journalctl -u dnsmasq -n 100 --no-pager || true
    exit 1
  fi
  LOGGER ok "dnsmasq is up"
}

init_dnsmasq() {
  LOGGER info "DNSMASQ: configuring DHCP/DNS for router mode"
  _load_env
  _purge_legacy_nm_snippet
  _render_wifi_ap_conf
  _sanitize_bind_options
  _check_ap_ip_presence
  _test_and_restart
  LOGGER ok "dnsmasq configured for interface ${WIRELESS_INTERFACE:-${WIRELESS_IF:-<unset>}} (AP ${AP_IP})"
}
