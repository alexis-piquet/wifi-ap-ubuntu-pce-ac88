#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../lib/log.sh"
. "$SCRIPT_DIR/../.env"

section "ENABLE NAT & FORWARDING"

step "Enabling IPv4 forwarding"
sudo sysctl -w net.ipv4.ip_forward=1
sudo sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf

step "Setting up iptables NAT rule"
sudo iptables -t nat -A POSTROUTING -o $ethernet_id -j MASQUERADE

step "Installing iptables-persistent"
sudo apt install -y iptables-persistent

ok "NAT and forwarding enabled and persistent"
