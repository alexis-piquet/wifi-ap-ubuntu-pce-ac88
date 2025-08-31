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

  : "${NET_MODE:=router}"             # router | bridge
  : "${ETHERNET_IF:?Set ETHERNET_IF in .env}"
  : "${WIRELESS_IF:=}"                # may be empty if firmware not yet ready

  if [[ "$NET_MODE" != "router" ]]; then
    LOGGER info "NET_MODE=$NET_MODE → NAT not required (skipping)."
    exit 0
  fi
}

_enable_ip_forwarding() {
  LOGGER step "Enabling IPv4 forwarding (runtime + persistent)"
  # Runtime
  sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null

  # Persistent via sysctl.d (clean, without editing /etc/sysctl.conf)
  local sysctl_file="/etc/sysctl.d/99-wifi-ap.conf"
  echo "net.ipv4.ip_forward = 1" | sudo tee "$sysctl_file" >/dev/null
  sudo sysctl --system >/dev/null
}

_apply_nat_rules() {
  # Rules:
  # 1) FORWARD: Traffic from Wi-Fi to Ethernet
  # 2) FORWARD: Return traffic ESTABLISHED,RELATED
  # 3) MASQUERADE on the WAN interface (ETHERNET_IF)
  LOGGER step "Applying iptables rules (idempotent)"

  # 1) Forward AP -> WAN
  sudo iptables -C FORWARD -i "$WIRELESS_IF" -o "$ETHERNET_IF" -j ACCEPT 2>/dev/null \
    || sudo iptables -A FORWARD -i "$WIRELESS_IF" -o "$ETHERNET_IF" -j ACCEPT

  # 2) Back traffic
  sudo iptables -C FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null \
    || sudo iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

  # 3) NAT
  sudo iptables -t nat -C POSTROUTING -o "$ETHERNET_IF" -j MASQUERADE 2>/dev/null \
    || sudo iptables -t nat -A POSTROUTING -o "$ETHERNET_IF" -j MASQUERADE

  LOGGER ok "iptables rules present"
}

_persist_rules_if_possible() {
  # Backup if iptables-persistent/netfilter-persistent is installed
  if command -v netfilter-persistent >/dev/null 2>&1; then
    LOGGER step "Saving rules via netfilter-persistent"
    sudo netfilter-persistent save || true
  elif systemctl list-unit-files | grep -q '^iptables-persistent\.service'; then
    LOGGER step "Saving rules via iptables-persistent"
    sudo service iptables-persistent save || true
  else
    # fallback: write rules.v4 if directory exists
    if [[ -d /etc/iptables ]]; then
      LOGGER step "Writing /etc/iptables/rules.v4 (fallback)"
      sudo iptables-save | sudo tee /etc/iptables/rules.v4 >/dev/null
    else
      LOGGER warn "iptables-persistent not installed — rules won't survive reboot (this is fine for dev)."
    fi
  fi
}

_warn_firewall_managers() {
  # Just informative: ufw/firewalld can impact FORWARD/NAT
  if systemctl is-active --quiet ufw; then
    LOGGER warn "UFW is active — ensure it allows forwarding & MASQUERADE for ${WIRELESS_IF}→${ETHERNET_IF}."
  fi
  if systemctl is-active --quiet firewalld; then
    LOGGER warn "firewalld is active — ensure a zone/masquerade is configured for ${ETHERNET_IF}."
  fi
}

init_nat() {
  LOGGER info "Setting up NAT and IPv4 forwarding (router mode)"
  _load_env

  if [[ -z "${WIRELESS_IF:-}" ]]; then
    LOGGER warn "WIRELESS_IF is empty — adding NAT rules anyway (they’ll match once Wi-Fi is up)."
  fi

  _enable_ip_forwarding
  _apply_nat_rules
  _persist_rules_if_possible
  _warn_firewall_managers

  LOGGER ok "NAT and forwarding configured (ETHERNET_IF=${ETHERNET_IF}, WIRELESS_IF=${WIRELESS_IF:-<none>})"
}
