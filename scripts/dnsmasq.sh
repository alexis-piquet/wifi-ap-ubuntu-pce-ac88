#!/usr/bin/env bash
set -euo pipefail

CURRENT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_PATH/../lib/utils.sh"

export LOG_NAMESPACE="[SCRIPTS][DNSMASQ]"
source_as "$CURRENT_PATH/../lib/log.sh" "LOGGER"

init() {
  LOGGER section "DNSMASQ: Setup DNS-MASQ for DHCP and DNS with ipset support"

  WIFI_INTERFACE="$(ip link | awk -F: '/^[0-9]+: wl/ { print $2; exit }' | xargs)"
  if [[ -z "$WIFI_INTERFACE" ]]; then
    LOGGER error "No Wi-Fi interface found"
    exit 1
  fi
  LOGGER info "Detected Wi-Fi interface: $WIFI_INTERFACE"

  LOGGER step "Creating dnsmasq.d directory"
  sudo mkdir -p /etc/NetworkManager/dnsmasq.d

  LOGGER step "Generating dnsmasq.conf"
  cat <<EOF | sudo tee /etc/NetworkManager/dnsmasq.d/dnsmasq.conf > /dev/null
interface=$WIFI_INTERFACE
dhcp-range=10.0.0.50,10.0.0.150,255.255.255.0,12h
cache-size=1500
ipset
conf-dir=/etc/dnsmasq.d
EOF

  LOGGER step "Configuring NetworkManager"
  sudo bash -c 'echo -e "[main]\ndns=dnsmasq" > /etc/NetworkManager/NetworkManager.conf'

  LOGGER ok "dnsmasq configured with interface '$WIFI_INTERFACE'"
}