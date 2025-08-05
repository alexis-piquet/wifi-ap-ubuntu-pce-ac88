#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../lib/log.sh"

section "Configure dnsmasq"

WIFI_INTERFACE="$(ip link | awk -F: '/^[0-9]+: wl/ { print $2; exit }' | xargs)"
if [[ -z "$WIFI_INTERFACE" ]]; then
  error "No Wi-Fi interface found"
  exit 1
fi
info "Detected Wi-Fi interface: $WIFI_INTERFACE"

step "Creating dnsmasq.d directory"
sudo mkdir -p /etc/NetworkManager/dnsmasq.d

step "Generating dnsmasq.conf"
cat <<EOF | sudo tee /etc/NetworkManager/dnsmasq.d/dnsmasq.conf > /dev/null
interface=$WIFI_INTERFACE
dhcp-range=10.0.0.50,10.0.0.150,255.255.255.0,12h
cache-size=1500
ipset
conf-dir=/etc/dnsmasq.d
EOF

step "Configuring NetworkManager"
sudo bash -c 'echo -e "[main]\ndns=dnsmasq" > /etc/NetworkManager/NetworkManager.conf'

ok "dnsmasq configured with interface '$WIFI_INTERFACE'"
