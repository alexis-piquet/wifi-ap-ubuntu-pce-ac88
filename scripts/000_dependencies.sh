#!/usr/bin/env bash
set -euo pipefail

CURRENT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_PATH/../lib/utils.sh"
source_as "$CURRENT_PATH/../lib/logger.sh" "LOGGER"

# Read optional .env for NET_MODE/NET_BACKEND (defaults if absent)
_load_env_if_present() {
  local env_file="$CURRENT_PATH/../.env"
  if [[ -f "$env_file" ]]; then
    # shellcheck source=/dev/null
    source "$env_file"
  fi
  : "${NET_MODE:=router}"       # router | bridge
  : "${NET_BACKEND:=netplan}"   # netplan | nm
}

_pkg_candidate() {
  # prints candidate version or "(none)"
  apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2; exit}' || echo "(none)"
}

_pkg_is_installed() {
  dpkg -s "$1" &>/dev/null
}

_preseed_noninteractive() {
  export DEBIAN_FRONTEND=noninteractive
  # Avoid iptables-persistent TUI prompts (only if we plan to install it)
  if [[ " ${WANTED_PKGS[*]} " == *" iptables-persistent "* ]]; then
    echo "iptables-persistent iptables-persistent/autosave_v4 boolean true"  | sudo debconf-set-selections || true
    echo "iptables-persistent iptables-persistent/autosave_v6 boolean false" | sudo debconf-set-selections || true
  fi
}

init_dependencies() {
  LOGGER info "Installing required dependencies (context-aware)"

  _load_env_if_present

  # --- Base build & tools
  BASE_PKGS=(
    build-essential pkg-config git curl wget
    iproute2 iw rfkill
    libssl-dev
    libnl-3-dev libnl-genl-3-dev libnl-route-3-dev
    libnfnetlink-dev
  )

  # Wireless regulatory db (crda is gone on récentes distros, keep best-effort)
  RADIO_PKGS=(wireless-regdb crda)

  # Network stack (mode-dependent)
  NET_PKGS=()
  if [[ "$NET_BACKEND" == "nm" ]]; then
    NET_PKGS+=(network-manager)
  fi

  if [[ "$NET_MODE" == "router" ]]; then
    NET_PKGS+=(dnsmasq iptables ipset iptables-persistent)
  else
    # bridge mode: iptables/ipset not strictly required; keep minimal
    NET_PKGS+=(iptables)
  fi

  # Compose wanted list, filter out packages not available on this distro
  WANTED_PKGS=("${BASE_PKGS[@]}" "${RADIO_PKGS[@]}" "${NET_PKGS[@]}")
  AVAILABLE_PKGS=()
  SKIPPED_PKGS=()
  for p in "${WANTED_PKGS[@]}"; do
    cand="$(_pkg_candidate "$p")"
    if [[ -n "$cand" && "$cand" != "(none)" ]]; then
      AVAILABLE_PKGS+=("$p")
    else
      SKIPPED_PKGS+=("$p")
    fi
  done

  if (( ${#SKIPPED_PKGS[@]} > 0 )); then
    LOGGER warn "Skipping unavailable packages: ${SKIPPED_PKGS[*]}"
  fi

  # Compute missing pkgs
  MISSING_PKGS=()
  for p in "${AVAILABLE_PKGS[@]}"; do
    _pkg_is_installed "$p" || MISSING_PKGS+=("$p")
  done

  if (( ${#MISSING_PKGS[@]} == 0 )); then
    LOGGER ok "All required packages already installed"
    return 0
  fi

  LOGGER step "Updating apt index"
  sudo apt-get update -y -qq

  _preseed_noninteractive
  LOGGER step "Installing: ${MISSING_PKGS[*]}"
  sudo apt-get install -y --no-install-recommends "${MISSING_PKGS[@]}"

  # Small post-hints
  if [[ " ${MISSING_PKGS[*]} " == *" network-manager "* ]]; then
    LOGGER info "NetworkManager installed (backend=nm). You may need a reboot if services conflict."
  fi
  if [[ " ${MISSING_PKGS[*]} " == *" dnsmasq "* && "$NET_MODE" == "router" ]]; then
    LOGGER info "dnsmasq installed (router mode). We'll sanitize bind options later."
  fi

  LOGGER ok "Dependencies installed"
}
