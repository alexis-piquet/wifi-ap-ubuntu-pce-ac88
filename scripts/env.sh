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

  LOGGER step "Ensuring bridge br0 exists and enslaving $ethernet_id"
  bridge_id="br0"

  # 0) Nettoyage d’anciens profils conflictuels
  nmcli -t -f NAME,DEVICE con show --active \
    | awk -F: -v d="$ethernet_id" '$2==d{print $1}' \
    | while read -r active_con; do
        LOGGER info "Detaching active connection on $ethernet_id: $active_con"
        nmcli con down "$active_con" || true
        nmcli con delete "$active_con" || true
      done

  # Supprime d’anciens profils de bridge si présents
  nmcli con delete br0                2>/dev/null || true
  nmcli con delete "br0-port-$ethernet_id" 2>/dev/null || true

  # 1) Créer le bridge
  nmcli con add type bridge ifname br0 con-name br0 ipv4.method auto ipv6.method ignore

  # 2) Ajouter le port de bridge (type correct: bridge-slave)
  nmcli con add type bridge-slave ifname "$ethernet_id" con-name "br0-port-$ethernet_id" master br0

  # 3) Monter le port puis le bridge (ou l’inverse si tu préfères)
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

  # Attendre que br0 soit visible et up
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

  # Write .env dans le répertoire courant (si tu veux un state-dir, adapte ici)
  printf "export ethernet_id=%s\nexport wireless_id=%s\nexport bridge_id=%s\n" \
    "$ethernet_id" "$wireless_id" "$bridge_id" > .env

  LOGGER ok "Environment written to .env"
}
