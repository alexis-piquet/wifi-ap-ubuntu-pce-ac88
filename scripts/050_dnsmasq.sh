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

  : "${NET_MODE:=router}"           # router | bridge
  : "${WIRELESS_IF:=}"              # may still be empty if firmware not ready
  : "${AP_CIDR:=}"                  # e.g. 10.0.0.1/24
  : "${AP_IP:=}"                    # may be set directly in .env
  : "${DHCP_START:=}"
  : "${DHCP_END:=}"

  # Compute AP_IP safely if not set
  if [[ -z "${AP_IP:-}" ]]; then
    if [[ -n "${AP_CIDR:-}" ]]; then
      AP_IP="${AP_CIDR%/*}"
    else
      AP_IP="10.0.0.1"
    fi
  fi

  # Compute DHCP range safely if not set (assume /24)
  if [[ -z "${DHCP_START:-}" || -z "${DHCP_END:-}" ]]; then
    local ap_net
    ap_net="$(printf "%s\n" "$AP_IP" | awk -F. '{printf "%d.%d.%d",$1,$2,$3}')"
    DHCP_START="${ap_net}.10"
    DHCP_END="${ap_net}.200"
  fi

  # Template expects WIRELESS_INTERFACE
  WIRELESS_INTERFACE="${WIRELESS_IF:-${WIRELESS_INTERFACE:-}}"

  if [[ "${NET_MODE}" != "router" ]]; then
    LOGGER info "NET_MODE=${NET_MODE} → dnsmasq not required (skipping)."
    exit 0
  fi

  if [[ -z "${WIRELESS_INTERFACE:-}" ]]; then
    LOGGER warn "WIRELESS_IF is empty — dnsmasq may fail to bind; continuing anyway."
  fi

  # Export only what the template/envsubst needs
  export WIRELESS_INTERFACE AP_IP DHCP_START DHCP_END
}

_render_wifi_ap_conf() {
  local tpl="$ROOT_DIR/config/dnsmasq/wifi-ap.conf"
  local dst="/etc/dnsmasq.d/wifi-ap.conf"

  LOGGER step "Rendering dnsmasq AP config → $dst"
  sudo install -d -m 0755 /etc/dnsmasq.d

  if [[ -f "$tpl" ]]; then
    if command -v envsubst >/dev/null 2>&1; then
      envsubst '$WIRELESS_INTERFACE$AP_IP$DHCP_START$DHCP_END' < "$tpl" \
        | sudo tee "$dst" >/dev/null
    else
      # Fallback without envsubst
      sudo sed \
        -e "s|\${WIRELESS_INTERFACE}|${WIRELESS_INTERFACE:-}|g" \
        -e "s|\${AP_IP}|${AP_IP:-}|g" \
        -e "s|\${DHCP_START}|${DHCP_START:-}|g" \
        -e "s|\${DHCP_END}|${DHCP_END:-}|g" \
        "$tpl" | sudo tee "$dst" >/dev/null
    fi
  else
    LOGGER warn "Missing $tpl — generating a minimal config"
    sudo tee "$dst" >/dev/null <<EOF
# listening only AP interface
interface=${WIRELESS_INTERFACE:-}
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

  sudo chmod 0644 "$dst"
  LOGGER ok "wifi-ap.conf ready"
}

_sanitize_bind_options() {
  LOGGER step "Sanitizing dnsmasq bind options (remove bind-dynamic / stray bind-interfaces)"

  # 1) /etc/default/dnsmasq (strip CLI bind flags)
  if [[ -f /etc/default/dnsmasq ]]; then
    sudo sed -i -E 's/(DNSMASQ_OPTS|OPTIONS)=.*$/DNSMASQ_OPTS=""/' /etc/default/dnsmasq 2>/dev/null || true
    sudo sed -i -E 's/--bind-(interfaces|dynamic)//g' /etc/default/dnsmasq || true
  fi

  # 2) main file
  sudo sed -i -E '/^\s*bind-(interfaces|dynamic)\s*$/d' /etc/dnsmasq.conf 2>/dev/null || true

  # 3) snippets (except our wifi-ap.conf)
  sudo find /etc/dnsmasq.d -maxdepth 1 -type f -name "*.conf" ! -name "wifi-ap.conf" -print0 \
    | xargs -0 -r sudo sed -i -E '/^\s*bind-(interfaces|dynamic)\s*$/d'

  # Ensure our file keeps bind-interfaces
  sudo sed -i -E 's/^\s*bind-(interfaces|dynamic)\s*$/bind-interfaces/' /etc/dnsmasq.d/wifi-ap.conf
}

_check_ap_ip_presence() {
  if [[ -n "${WIRELESS_INTERFACE:-}" ]]; then
    if ! ip -4 addr show dev "${WIRELESS_INTERFACE}" | grep -q " ${AP_IP}/"; then
      LOGGER warn "AP_IP ${AP_IP} not present on ${WIRELESS_INTERFACE}. (030_network.sh should assign it in router mode)"
    fi
  fi
}

_test_and_restart() {
  LOGGER step "Config test (dnsmasq --test with conf-dir)"
  if ! sudo dnsmasq --test --conf-file=/etc/dnsmasq.conf --conf-dir=/etc/dnsmasq.d; then
    LOGGER error "dnsmasq --test failed"
    exit 1
  fi

  # FYI: resolved may hold :53; we bind to the AP interface, so no conflict.
  if sudo ss -ltnp '( sport = :53 )' 2>/dev/null | grep -q systemd-resolved; then
    LOGGER info "systemd-resolved owns :53; dnsmasq is bound to ${WIRELESS_INTERFACE:-<unset>}:${AP_IP}."
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
  _render_wifi_ap_conf
  _sanitize_bind_options
  _check_ap_ip_presence
  _test_and_restart
  LOGGER ok "dnsmasq configured for interface ${WIRELESS_INTERFACE:-<unset>} (AP ${AP_IP})"
}
