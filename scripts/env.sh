#!/usr/bin/env bash
set -euo pipefail

CURRENT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_PATH/../lib/utils.sh"
source_as "$CURRENT_PATH/../lib/logger.sh" "LOGGER"

init_env() {
  LOGGER info "Ensuring NetworkManager is running and interfaces are managed"

  sudo systemctl enable --now NetworkManager

  if grep -q "managed=false" /etc/NetworkManager/NetworkManager.conf 2>/dev/null; then
    LOGGER warn "'managed=false' found in NetworkManager.conf — switching to 'managed=true'"
    sudo sed -i 's/managed=false/managed=true/' /etc/NetworkManager/NetworkManager.conf
    sudo systemctl restart NetworkManager
  fi

  if [[ -d /etc/netplan ]]; then
    if ! sudo grep -REq 'renderer:\s*NetworkManager' /etc/netplan/*.yaml 2>/dev/null; then
      LOGGER warn "Netplan renderer is not NetworkManager — switching"
      sudo cp -an /etc/netplan "/etc/netplan.backup.$(date +%Y%m%d%H%M%S)"
      sudo tee /etc/netplan/99-network-manager.yaml >/dev/null <<'EOF'
network:
  version: 2
  renderer: NetworkManager
EOF
      sudo netplan apply || { LOGGER error "netplan apply failed"; exit 1; }
    fi
  fi

  LOGGER step "Detecting interfaces via nmcli"
  ethernet_id=$(nmcli -t -f DEVICE,TYPE,STATE dev | awk -F: '$2=="ethernet" && $3!="unavailable"{print $1; exit}' || true)
  wireless_id=$(nmcli -t -f DEVICE,TYPE,STATE dev | awk -F: '$2=="wifi"     && $3!="unavailable"{print $1; exit}' || true)

  if [[ -z "$ethernet_id" ]]; then
    LOGGER error "Ethernet interface not found or still unmanaged"
    nmcli device status
    exit 1
  fi

  if [[ -z "$wireless_id" ]]; then
    LOGGER warn "Wi-Fi interface not found (yet) — this may be expected before firmware setup"
  fi

  if nmcli -t -f DEVICE,STATE dev | grep -q "^${ethernet_id}:unmanaged$"; then
    LOGGER warn "$ethernet_id is unmanaged — asking NM to manage it"
    nmcli dev set "$ethernet_id" managed yes || true
  fi

  LOGGER step "Ensuring bridge br0 exists and enslaving $ethernet_id"
  bridge_id="br0"

  nmcli -t -f NAME,DEVICE con show --active \
    | awk -F: -v d="$ethernet_id" '$2==d{print $1}' \
    | while read -r c; do
        LOGGER info "Detaching active connection on $ethernet_id: $c"
        nmcli con down "$c" || true
        nmcli con delete "$c" || true
      done

  nmcli con delete br0                       2>/dev/null || true
  nmcli con delete "br0-port-$ethernet_id"  2>/dev/null || true
  nmcli con delete "bridge-slave-$ethernet_id" 2>/dev/null || true

  nmcli con add type bridge ifname br0 con-name br0 ipv4.method auto ipv6.method ignore
  nmcli con add type bridge-slave ifname "$ethernet_id" con-name "br0-port-$ethernet_id" master br0

  if nmcli -t -f DEVICE,STATE dev | grep -q "^${ethernet_id}:unmanaged$"; then
    LOGGER error "$ethernet_id is still unmanaged by NetworkManager.
• Vérifie netplan (renderer: NetworkManager) et relance.
• Vérifie qu’aucune conf /etc/network/interfaces* ne gère $ethernet_id.
Etat courant:"
    nmcli device status
    exit 1
  fi

  if ! nmcli con up "br0-port-$ethernet_id"; then
    LOGGER error "Failed to bring up bridge slave $ethernet_id"
    nmcli -f NAME,UUID,TYPE,DEVICE con
    nmcli dev
    exit 1
  fi

  if ! nmcli con up br0; then
    LOGGER error "Failed to bring up bridge br0"
    nmcli -f NAME,UUID,TYPE,DEVICE con
    exit 1
  fi

  for i in {1..10}; do
    if ip link show br0 &>/dev/null; then
      state=$(cat /sys/class/net/br0/operstate 2>/dev/null || echo down)
      [[ "$state" == "up" || "$state" == "unknown" ]] && break
    fi
    LOGGER info "Waiting for br0 to be up…"
    sleep 1
  done

  LOGGER info "Ethernet: $ethernet_id"
  LOGGER info "Wireless: $wireless_id"
  LOGGER info "Bridge:   $bridge_id"

  printf "export ethernet_id=%s\nexport wireless_id=%s\nexport bridge_id=%s\n" \
    "$ethernet_id" "$wireless_id" "$bridge_id" > .env

  LOGGER ok "Environment written to .env"
}
