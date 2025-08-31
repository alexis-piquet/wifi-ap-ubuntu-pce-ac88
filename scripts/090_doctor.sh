#!/usr/bin/env bash
set -euo pipefail

CURRENT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$CURRENT_PATH/.."

source "$ROOT_DIR/lib/utils.sh"
source_as "$ROOT_DIR/lib/logger.sh" "LOGGER"

# ──────────────────────────────────────────────────────────────────────────────
# Flags
# ──────────────────────────────────────────────────────────────────────────────
FIX=false
[[ "${1:-}" =~ ^(--fix|-f)$ ]] && FIX=true

# ──────────────────────────────────────────────────────────────────────────────
# Environment
# ──────────────────────────────────────────────────────────────────────────────
NET_MODE="router"   # router | bridge
ETHERNET_IF=""      # e.g. ens18
WIRELESS_IF=""      # e.g. wls16
BRIDGE_IF="br0"
AP_CIDR=""
AP_IP=""
WIRELESS_COUNTRY="${WIRELESS_COUNTRY:-FR}"

DNSMASQ_D="/etc/dnsmasq.d"
DNSMASQ_AP_CONF="$DNSMASQ_D/wifi-ap.conf"
HOSTAPD_CONF="/etc/hostapd/hostapd.conf"

ALLOWLIST_DIR="$ROOT_DIR/config/allowlist"
ALLOW_ALL_IPS_FILE="$ALLOWLIST_DIR/allow_all_ips.txt"
WHITELIST_FILE="$ALLOWLIST_DIR/whitelist.txt"

_do_if_fix() { [[ "$FIX" == true ]] || return 0; "$@"; }

_cmd_ok() { command -v "$1" >/dev/null 2>&1; }

_load_env() {
  local env_file="$ROOT_DIR/.env"
  [[ -f "$env_file" ]] || { LOGGER error "Missing .env — run 010_env.sh first"; exit 1; }
  # shellcheck disable=SC1090
  source "$env_file"

  NET_MODE="${NET_MODE:-router}"
  ETHERNET_IF="${ETHERNET_IF:-${ethernet_id:-}}"
  WIRELESS_IF="${WIRELESS_IF:-${wireless_id:-}}"
  BRIDGE_IF="${BRIDGE_IF:-${bridge_id:-br0}}"
  AP_CIDR="${AP_CIDR:-${AP_CIDR:-${AP_CIDR_ENV:-}}}"
  AP_IP="${AP_IP:-${AP_CIDR%/*}}"
  [[ -z "$AP_IP" ]] && AP_IP="10.0.0.1"

  LOGGER info "NET_MODE=$NET_MODE  ETH=${ETHERNET_IF:-<none>}  WIFI=${WIRELESS_IF:-<none>}  BR=$BRIDGE_IF  AP_IP=$AP_IP  FIX=$FIX"
}

_section() { LOGGER step "$1"; }

_try() { "$@" || true; }

# ──────────────────────────────────────────────────────────────────────────────
# Basic sanity: rfkill / interface presence / iw capabilities
# ──────────────────────────────────────────────────────────────────────────────
_check_rfkill() {
  _section "rfkill"
  if _cmd_ok rfkill; then
    rfkill list || true
    if rfkill list | grep -qi "Soft blocked: yes"; then
      LOGGER warn "Some radios are soft-blocked."
      if [[ "$FIX" == true ]]; then
        LOGGER info "Unblocking Wi-Fi (rfkill)"
        sudo rfkill unblock wifi
      fi
    fi
  fi
}

_check_ifaces() {
  _section "Interfaces (ip -br addr / link)"
  ip -br addr || true
  ip -br link || true

  if [[ -n "${WIRELESS_IF:-}" && $(ip -o link show | awk -F': ' '{print $2}' | grep -Fx "$WIRELESS_IF" | wc -l) -eq 1 ]]; then
    LOGGER ok "Wireless IF present: $WIRELESS_IF"
  else
    LOGGER error "WIRELESS_IF missing/empty — hostapd will not start"
  fi

  if [[ "$NET_MODE" == "router" ]]; then
    [[ -n "${ETHERNET_IF:-}" ]] && ip link show "$ETHERNET_IF" &>/dev/null \
      && LOGGER ok "Ethernet IF present: $ETHERNET_IF" \
      || LOGGER warn "ETHERNET_IF missing — NAT / Internet uplink may fail"
  else
    ip link show "$BRIDGE_IF" &>/dev/null \
      && LOGGER ok "Bridge present: $BRIDGE_IF" \
      || LOGGER warn "Bridge expected but not found: $BRIDGE_IF"
  fi
}

_check_iw_cap() {
  _section "Wi-Fi capabilities (iw list)"
  if _cmd_ok iw; then
    if iw list | awk '/Supported interface modes:/,/^$/' | grep -q ' AP'; then
      LOGGER ok "Driver reports AP mode support"
    else
      LOGGER error "Driver/firmware does not declare AP mode"
    fi
    LOGGER info "Regdom:"
    iw reg get || true
    # Apply regulatory domain if requested
    
    if [[ "$FIX" == true ]]; then
      LOGGER info "Setting regdom to $WIRELESS_COUNTRY"
      sudo iw reg set "$WIRELESS_COUNTRY" || true
    fi
  else
    LOGGER warn "iw not installed"
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Ensure NM/wpa_supplicant don’t own the AP interface
# ──────────────────────────────────────────────────────────────────────────────
_release_nm_and_wpa() {
  _section "NetworkManager / wpa_supplicant"
  if _cmd_ok nmcli; then
    nmcli dev status || true
    if nmcli dev status | awk -v ifc="$WIRELESS_IF" '$1==ifc{print $3}' | grep -vq "^unmanaged$"; then
      LOGGER warn "NetworkManager manages $WIRELESS_IF"
      if $FIX; then
        LOGGER info "Marking $WIRELESS_IF as unmanaged for NM"
        sudo mkdir -p /etc/NetworkManager/conf.d
        printf "[keyfile]\nunmanaged-devices=interface-name:%s\n" "$WIRELESS_IF" \
          | sudo tee /etc/NetworkManager/conf.d/99-unmanaged-wifi-ap.conf >/dev/null
        sudo systemctl restart NetworkManager
      fi
    else
      LOGGER ok "NetworkManager does not manage $WIRELESS_IF"
    fi
  fi

  # wpa_supplicant
  if systemctl list-unit-files | grep -q 'wpa_supplicant'; then
    if systemctl is-active --quiet "wpa_supplicant@$WIRELESS_IF.service"; then
      LOGGER warn "wpa_supplicant@$WIRELESS_IF is active"
      
      if [[ "$FIX" == true ]]; then
        sudo systemctl stop "wpa_supplicant@$WIRELESS_IF.service"
        sudo systemctl mask "wpa_supplicant@$WIRELESS_IF.service" || true
      fi
    fi
    if systemctl is-active --quiet wpa_supplicant; then
      LOGGER warn "wpa_supplicant is active (global)"
      
      if [[ "$FIX" == true ]]; then
        sudo systemctl stop wpa_supplicant || true
      fi
    fi
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Bring up AP IP & link
# ──────────────────────────────────────────────────────────────────────────────
_ensure_ap_ip() {
  [[ -z "${WIRELESS_IF:-}" ]] && return 0
  _section "AP link & IP"
  if ! ip -4 addr show dev "$WIRELESS_IF" | grep -q " $AP_IP/"; then
    LOGGER warn "No $AP_IP/24 on $WIRELESS_IF"
    if $FIX; then
      sudo ip link set "$WIRELESS_IF" down || true
      sudo ip addr flush dev "$WIRELESS_IF" || true
      sudo ip link set "$WIRELESS_IF" up
      sudo ip addr replace "$AP_IP/24" dev "$WIRELESS_IF"
    fi
  else
    LOGGER ok "$AP_IP/24 present on $WIRELESS_IF"
  fi
  ip -br addr show dev "$WIRELESS_IF" || true
}

# ──────────────────────────────────────────────────────────────────────────────
# dnsmasq checks (router mode)
# ──────────────────────────────────────────────────────────────────────────────
_check_dnsmasq() {
  [[ "$NET_MODE" == "router" ]] || return 0
  _section "dnsmasq"
  if ! systemctl list-unit-files | grep -q '^dnsmasq\.service'; then
    LOGGER warn "dnsmasq.service not installed"
    return 0
  fi

  if [[ -f "$DNSMASQ_AP_CONF" ]]; then
    LOGGER info "AP conf: $DNSMASQ_AP_CONF"
    sudo sed -n '1,120p' "$DNSMASQ_AP_CONF" | sed 's/^/  /'
    # Check interface and listening IP
    if ! grep -Eq "^\s*interface\s*=\s*${WIRELESS_IF}\s*$" "$DNSMASQ_AP_CONF"; then
      LOGGER warn "dnsmasq AP conf does not bind interface=$WIRELESS_IF"
    fi
    if ! grep -Eq "^\s*listen-address\s*=\s*${AP_IP}\s*$" "$DNSMASQ_AP_CONF"; then
      LOGGER warn "dnsmasq AP conf does not listen-address=$AP_IP"
    fi
  else
    LOGGER warn "Missing $DNSMASQ_AP_CONF"
  fi

  LOGGER info "Port 53 listeners:"
  sudo ss -ltnp '( sport = :53 )' || true

  if sudo dnsmasq --test --conf-file=/etc/dnsmasq.conf --conf-dir="$DNSMASQ_D"; then
    LOGGER ok "dnsmasq config test OK"
  else
    LOGGER error "dnsmasq --test failed"
  fi

  if ! systemctl is-active --quiet dnsmasq; then
    LOGGER warn "dnsmasq inactive"
    
    if [[ "$FIX" == true ]]; then
      sudo systemctl restart dnsmasq
    fi
  else
    LOGGER ok "dnsmasq running"
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# NAT / iptables (router mode)
# ──────────────────────────────────────────────────────────────────────────────
_check_nat() {
  [[ "$NET_MODE" == "router" ]] || return 0
  _section "NAT / iptables"

  if [[ -n "${ETHERNET_IF:-}" ]]; then
    if sudo iptables -t nat -C POSTROUTING -o "$ETHERNET_IF" -j MASQUERADE 2>/dev/null; then
      LOGGER ok "MASQUERADE on $ETHERNET_IF present"
    else
      LOGGER warn "No MASQUERADE on $ETHERNET_IF"
      if [[ "$FIX" == true ]]; then
        sudo iptables -t nat -A POSTROUTING -o "$ETHERNET_IF" -j MASQUERADE
      fi
    fi
  fi

  if sudo iptables -C FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null; then
    LOGGER ok "FORWARD ESTABLISHED,RELATED present"
  else
    LOGGER warn "FORWARD ESTABLISHED,RELATED missing"
    
    if [[ "$FIX" == true ]]; then
      sudo iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
    fi
  fi

  # Optional: save rules (if netfilter-persistent plugin available)
    
  if [[ "$FIX" == true ]]; then
    _try sudo run-parts --verbose /usr/share/netfilter-persistent/plugins.d
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Allowlist / ipset (router mode)
# ──────────────────────────────────────────────────────────────────────────────
_check_allowlist() {
  [[ "$NET_MODE" == "router" ]] || return 0
  _section "Allowlist (ipset)"
  if sudo ipset list whitelist &>/dev/null; then
    sudo ipset list whitelist | head -n 20 || true
  else
    LOGGER warn "ipset 'whitelist' missing"
  fi
  if sudo ipset list allow_all &>/dev/null; then
    sudo ipset list allow_all | head -n 20 || true
  else
    LOGGER warn "ipset 'allow_all' missing"
  fi

  # Basic consistency check with files (if present)
  if [[ -f "$ALLOW_ALL_IPS_FILE" ]]; then
    local nfile nset
    nfile=$(grep -Evc '^\s*($|#)' "$ALLOW_ALL_IPS_FILE" || true)
    nset=$(sudo ipset list allow_all 2>/dev/null | grep -Ec '^\s*([0-9]{1,3}\.){3}[0-9]{1,3}\s*$' || true)
    LOGGER info "allow_all: file=$nfile  set=$nset"
    [[ "$nfile" -gt 0 && "$nset" -eq 0 ]] && LOGGER warn "allow_all file not empty but set is empty (remember to run 070_allowlist.sh)"
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# hostapd
# ──────────────────────────────────────────────────────────────────────────────
_check_hostapd() {
  _section "hostapd"
  if [[ -f "$HOSTAPD_CONF" ]]; then
    LOGGER ok "$HOSTAPD_CONF present"
    sudo sed -n '1,80p' "$HOSTAPD_CONF" | sed 's/^/  /'
    # SSID visibility
    if grep -Eq '^\s*ignore_broadcast_ssid\s*=\s*1\s*$' "$HOSTAPD_CONF"; then
      LOGGER warn "ignore_broadcast_ssid=1 → Hidden SSID"
    fi
    # Config test
    if _cmd_ok hostapd; then
      if hostapd -t "$HOSTAPD_CONF"; then
        LOGGER ok "hostapd -t OK"
      else
        LOGGER error "hostapd -t FAILED"
      fi
    fi
  else
    LOGGER error "$HOSTAPD_CONF missing"
  fi

  # Service state
  if systemctl list-unit-files | grep -q '^hostapd\.service'; then
    if systemctl is-active --quiet hostapd; then
      LOGGER ok "hostapd running"
    else
      LOGGER warn "hostapd inactive"
      if [[ "$FIX" == true ]]; then
        sudo systemctl restart hostapd || true
      fi
    fi
    # Recent logs
    sudo journalctl -u hostapd -n 60 --no-pager || true
  else
    LOGGER warn "hostapd.service not installed/enabled"
  fi

  # Link UP and mode
  ip -br link show dev "$WIRELESS_IF" || true
  if _cmd_ok iw; then
    iw dev "$WIRELESS_IF" info || true
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Router quick smoke (ARP/DNS)
# ──────────────────────────────────────────────────────────────────────────────
_quick_smoke_router() {
  [[ "$NET_MODE" == "router" ]] || return 0
  _section "Quick smoke (router)"
  # Port 53 bind on AP_IP
  sudo ss -ltnp | grep -E "LISTEN .* ${AP_IP}:53" || LOGGER warn "dnsmasq does not seem to listen on ${AP_IP}:53"
  # DHCP leases
  [[ -f /var/lib/misc/dnsmasq.leases ]] && { LOGGER info "dnsmasq.leases:"; sudo cat /var/lib/misc/dnsmasq.leases || true; }
}

# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────
init_doctor() {
  LOGGER info "Doctor / Diagnostics (with optional --fix)"
  _load_env
  _check_rfkill
  _release_nm_and_wpa
  _check_ifaces
  _check_iw_cap
  _ensure_ap_ip
  _check_dnsmasq
  _check_nat
  _check_allowlist
  _check_hostapd
  _quick_smoke_router

  LOGGER ok "Diagnostics completed"
  [[ "$FIX" == true ]] && LOGGER ok "Best-effort fixes applied (where safe)."
}
