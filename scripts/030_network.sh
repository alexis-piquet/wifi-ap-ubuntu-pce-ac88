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
  : "${NET_BACKEND:=netplan}"      # netplan | nm
  : "${ETHERNET_IF:?Set ETHERNET_IF in .env}"
  : "${WIRELESS_IF:=}"             # may be empty before firmware is ready
  : "${BRIDGE_IF:=br0}"
  : "${AP_CIDR:=10.0.0.1/24}"
  : "${AP_IP:=${AP_CIDR%/*}}"
}

_wait_for_link_up() {
  local ifc="$1"
  for _ in {1..10}; do
    if ip link show "$ifc" &>/dev/null; then
      local st
      st="$(cat "/sys/class/net/$ifc/operstate" 2>/dev/null || echo down)"
      [[ "$st" == "up" || "$st" == "unknown" ]] && return 0
    fi
    sleep 1
  done
  return 1
}

_apply_router_runtime() {
  if [[ -z "$WIRELESS_IF" ]]; then
    LOGGER warn "WIRELESS_IF is empty (firmware not ready?) — skipping AP IP assignment"
    return 0
  fi

  LOGGER step "Bringing up $WIRELESS_IF and assigning $AP_CIDR"
  sudo ip link set "$WIRELESS_IF" up || true
  sudo ip addr replace "$AP_CIDR" dev "$WIRELESS_IF"
  _wait_for_link_up "$WIRELESS_IF" || LOGGER warn "$WIRELESS_IF did not report UP (continuing)"
  LOGGER ok "AP IP set on $WIRELESS_IF ($AP_CIDR)"
  LOGGER info "Current: $(ip -br addr show "$WIRELESS_IF" | awk '{$1=$1;print}')"
}

_render_netplan_bridge() {
  local tpl="$ROOT_DIR/config/netplan/60-br0.yaml.tpl"
  local dst="/etc/netplan/60-br0.yaml"

  LOGGER step "Writing netplan bridge config to $dst (BRIDGE_IF=$BRIDGE_IF ⇐ $ETHERNET_IF)"
  sudo mkdir -p /etc/netplan
  sudo cp -an /etc/netplan "/etc/netplan.backup.$(date +%Y%m%d%H%M%S)"

  if [[ -f "$tpl" ]]; then
    if command -v envsubst >/dev/null 2>&1; then
      ( export ETHERNET_IF BRIDGE_IF; envsubst < "$tpl" | sudo tee "$dst" >/dev/null )
    else
      # basic replacement if envsubst is not available
      sudo sed -e "s/\${ETHERNET_IF}/$ETHERNET_IF/g" -e "s/\${BRIDGE_IF}/$BRIDGE_IF/g" "$tpl" | sudo tee "$dst" >/dev/null
    fi
  else
    # minimal fallback
    LOGGER warn "Missing template $tpl — writing minimal config"
    # shellcheck disable=SC2016
    sudo tee "$dst" >/dev/null <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${ETHERNET_IF}:
      dhcp4: false
      dhcp6: false
  bridges:
    ${BRIDGE_IF}:
      interfaces: [${ETHERNET_IF}]
      dhcp4: true
      dhcp6: false
      parameters:
        stp: false
        forward-delay: 0
EOF
  fi

  LOGGER step "Applying netplan and enabling systemd-networkd"
  sudo systemctl enable --now systemd-networkd systemd-networkd-wait-online >/dev/null 2>&1 || true
  sudo netplan apply

  _wait_for_link_up "$BRIDGE_IF" || {
    LOGGER error "$BRIDGE_IF did not come up after netplan apply"
    ip -br addr || true
    exit 1
  }
  LOGGER ok "Bridge $BRIDGE_IF is up"
}

_nm_ensure_running() {
  sudo systemctl unmask NetworkManager >/dev/null 2>&1 || true
  sudo systemctl enable NetworkManager  >/dev/null 2>&1 || true
  sudo systemctl restart NetworkManager >/dev/null 2>&1 || sudo systemctl start NetworkManager >/dev/null 2>&1 || true
  for _ in {1..20}; do
    if systemctl is-active --quiet NetworkManager && nmcli -t -f RUNNING general 2>/dev/null | grep -q '^running$'; then
      return 0
    fi
    sleep 1
  done
  LOGGER error "NetworkManager is not running"
  exit 1
}

_apply_nm_bridge() {
  LOGGER step "Creating bridge $BRIDGE_IF with NetworkManager (port: $ETHERNET_IF)"
  _nm_ensure_running

  # clean profile if it exists
  nmcli -t -f NAME,DEVICE con show --active \
    | awk -F: -v d="$ETHERNET_IF" '$2==d{print $1}' \
    | while read -r c; do nmcli con down "$c" || true; nmcli con delete "$c" || true; done
  nmcli con delete "$BRIDGE_IF" 2>/dev/null || true
  nmcli con delete "br0-port-$ETHERNET_IF" 2>/dev/null || true
  nmcli con delete "bridge-slave-$ETHERNET_IF" 2>/dev/null || true

  nmcli con add type bridge       ifname "$BRIDGE_IF" con-name "$BRIDGE_IF" ipv4.method auto ipv6.method ignore
  nmcli con add type bridge-slave ifname "$ETHERNET_IF" con-name "br0-port-$ETHERNET_IF" master "$BRIDGE_IF"

  nmcli dev set "$ETHERNET_IF" managed yes || true

  nmcli con up "br0-port-$ETHERNET_IF"
  nmcli con up "$BRIDGE_IF"

  _wait_for_link_up "$BRIDGE_IF" || LOGGER warn "$BRIDGE_IF did not report UP (continuing)"
  LOGGER ok "Bridge $BRIDGE_IF is configured via NetworkManager"
}

init_network() {
  _load_env

  LOGGER info "NET_MODE=${NET_MODE}  NET_BACKEND=${NET_BACKEND}"
  LOGGER info "ETHERNET_IF=${ETHERNET_IF}  WIRELESS_IF=${WIRELESS_IF:-<none>}  BRIDGE_IF=${BRIDGE_IF}"

  case "$NET_MODE" in
    router)
      LOGGER step "Router mode: no bridge; assigning AP IP at runtime"
      _apply_router_runtime
      ;;
    bridge)
      LOGGER step "Bridge mode: creating $BRIDGE_IF over $ETHERNET_IF"
      if [[ "$NET_BACKEND" == "netplan" ]]; then
        _render_netplan_bridge
      else
        _apply_nm_bridge
      fi
      ;;
    *)
      LOGGER error "Unknown NET_MODE: $NET_MODE"
      exit 1
      ;;
  esac

  LOGGER ok "Network configuration applied for mode '$NET_MODE'"
}
