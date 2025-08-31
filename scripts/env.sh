#!/usr/bin/env bash
set -euo pipefail

CURRENT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_PATH/../lib/utils.sh"
source_as "$CURRENT_PATH/../lib/logger.sh" "LOGGER"

#!/usr/bin/env bash
set -euo pipefail

CURRENT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_PATH/../lib/utils.sh"
source_as "$CURRENT_PATH/../lib/logger.sh" "LOGGER"

ensure_nm_up() {
  LOGGER step "Ensuring NetworkManager is active"
  sudo systemctl unmask NetworkManager  >/dev/null 2>&1 || true
  sudo systemctl enable NetworkManager  >/dev/null 2>&1 || true
  sudo systemctl restart NetworkManager >/dev/null 2>&1 || sudo systemctl start NetworkManager >/dev/null 2>&1 || true

  for i in {1..20}; do
    if systemctl is-active --quiet NetworkManager; then
      if nmcli -t -f RUNNING general 2>/dev/null | grep -q '^running$'; then
        return 0
      fi
    fi
    sleep 1
  done

  LOGGER error "NetworkManager did not come up."
  systemctl status NetworkManager --no-pager || true
  journalctl -u NetworkManager -n 50 --no-pager || true
  exit 1
}

init_env() {
  LOGGER info "Ensuring NetworkManager is running and interfaces are managed"

  if grep -q "managed=false" /etc/NetworkManager/NetworkManager.conf 2>/dev/null; then
    LOGGER warn "'managed=false' found in NetworkManager.conf — switching to 'managed=true'"
    sudo sed -i 's/managed=false/managed=true/' /etc/NetworkManager/NetworkManager.conf
  fi

  switched_renderer=0
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
      switched_renderer=1
    fi
  fi

  ensure_nm_up

  LOGGER step "Detecting interfaces via nmcli"
  ethernet_id=$(nmcli -t -f DEVICE,TYPE,STATE dev | awk -F: '$2=="ethernet" && $3!="unavailable"{print $1; exit}' || true)
  wireless_id=$(nmcli -t -f DEVICE,TYPE,STATE dev | awk -F: '$2=="wifi"     && $3!="unavailable"{print $1; exit}' || true)

  if [[ -z "$ethernet_id" ]]; then
    LOGGER error "Ethernet interface not found or still unmanaged"
    nmcli device status || true
    exit 1
  fi

  if [[ -z "$wireless_id" ]]; then
    LOGGER warn "Wi-Fi interface not found (yet) — this may be expected before firmware setup"
  fi

  LOGGER step "Ensuring bridge br0 exists and enslaving $ethernet_id"
  bridge_id="br0"

  nmcli -t -f NAME,DEVICE con show --active \
    | awk -F: -v d="$ethernet_id" '$2==d{print $1}' \
    | while read -r c; do nmcli con down "$c" || true; nmcli con delete "$c" || true; done
  nmcli con delete br0 2>/dev/null || true
  nmcli con delete "br0-port-$ethernet_id" 2>/dev/null || true
  nmcli con delete "bridge-slave-$ethernet_id" 2>/dev/null || true

  nmcli con add type bridge       ifname br0            con-name br0 ipv4.method auto ipv6.method ignore
  nmcli con add type bridge-slave ifname "$ethernet_id" con-name "br0-port-$ethernet_id" master br0

  if nmcli -t -f DEVICE,STATE dev | grep -q "^${ethernet_id}:unmanaged$"; then
    LOGGER warn "$ethernet_id is unmanaged — asking NM to manage it"
    nmcli dev set "$ethernet_id" managed yes || true
    sleep 1
  fi

  if ! nmcli con up "br0-port-$ethernet_id"; then
    LOGGER error "Failed to bring up bridge slave $ethernet_id"
    nmcli -f NAME,UUID,TYPE,DEVICE con || true
    nmcli dev || true
    exit 1
  fi

  if ! nmcli con up br0; then
    LOGGER error "Failed to bring up bridge br0"
    nmcli -f NAME,UUID,TYPE,DEVICE con || true
    exit 1
  fi

  LOGGER info "Ethernet: $ethernet_id"
  LOGGER info "Wireless: $wireless_id"
  LOGGER info "Bridge:   $bridge_id"

  printf "export ethernet_id=%s\nexport wireless_id=%s\nexport bridge_id=%s\n" \
    "$ethernet_id" "$wireless_id" "$bridge_id" > .env

  LOGGER ok "Environment written to .env"
}
