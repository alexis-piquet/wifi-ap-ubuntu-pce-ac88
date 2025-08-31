#!/usr/bin/env bash
set -euo pipefail

CURRENT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$CURRENT_PATH/.."

source "$ROOT_DIR/lib/utils.sh"
source_as "$ROOT_DIR/lib/logger.sh" "LOGGER"

# ─────────────────────────── helpers ───────────────────────────

_load_env() {
  local env_file="$ROOT_DIR/.env"
  if [[ ! -f "$env_file" ]]; then
    LOGGER error "Missing .env file – run 010_env.sh first"
    exit 1
  fi
  # shellcheck source=/dev/null
  source "$env_file"

  # Back-compat: accept old names if new ones are not defined
  : "${WIRELESS_IF:=${WIRELESS_IF:-}}"
  : "${WIRELESS_SSID:=${SSID:-wifi-ap}}"
  : "${WIRELESS_PASSWORD:=change-me-please}"
  : "${WIRELESS_COUNTRY:=${COUNTRY:-FR}}"
  : "${NET_MODE:=router}"         # router | bridge
  : "${BRIDGE_IF:=br0}"

  # sanity
  if [[ -z "${WIRELESS_IF:-}" ]]; then
    LOGGER warn "WIRELESS_IF is empty (firmware/driver not ready yet). We'll still install & render config."
  fi
  local pwlen=${#WIRELESS_PASSWORD}
  if (( pwlen < 8 || pwlen > 63 )); then
    LOGGER warn "WIRELESS_PASSWORD length should be 8..63 characters (current: ${pwlen})"
  fi
  if ! [[ "$WIRELESS_COUNTRY" =~ ^[A-Z]{2}$ ]]; then
    LOGGER warn "WIRELESS_COUNTRY should be a 2-letter code (e.g. FR, US). Current: '${WIRELESS_COUNTRY}'"
  fi
}

_rfkill_and_regdomain() {
  if command -v rfkill >/dev/null 2>&1; then
    LOGGER step "Unblocking Wi-Fi via rfkill"
    sudo rfkill unblock wifi || true
  fi
  if command -v iw >/dev/null 2>&1; then
    LOGGER info "Setting regulatory domain (best-effort): iw reg set ${WIRELESS_COUNTRY}"
    sudo iw reg set "${WIRELESS_COUNTRY}" || true
  fi
}

_build_install_hostapd() {
  local method="${HOSTAPD_INSTALL_METHOD:-build}"   # build | apt

  if [[ "$method" == "apt" ]]; then
    LOGGER step "Installing hostapd via apt"
    sudo apt-get update -y -qq
    sudo apt-get install -y --no-install-recommends hostapd
    return 0
  fi

  LOGGER step "Building hostapd from source"
  export GIT_TERMINAL_PROMPT=0
  local REPO_URL="${HOSTAPD_REPO_URL:-https://w1.fi/hostap.git}"
  local BUILD_DIR="${HOSTAPD_BUILD_DIR:-$HOME/hostap_build}"
  local REPO_DIR="$BUILD_DIR/hostap"

  mkdir -p "$BUILD_DIR"
  pushd "$BUILD_DIR" >/dev/null

  LOGGER info "Checking repo reachability: $REPO_URL"
  if ! git ls-remote --exit-code "$REPO_URL" &>/dev/null; then
    LOGGER error "Cannot reach repo: $REPO_URL (set HOSTAPD_REPO_URL)"
    popd >/dev/null || true
    exit 1
  fi

  local DEFAULT_BRANCH
  DEFAULT_BRANCH="$(git ls-remote --symref "$REPO_URL" HEAD | awk '/^ref:/ {sub("refs/heads/","",$2); print $2}')"
  local BRANCH="${HOSTAPD_BRANCH:-${DEFAULT_BRANCH:-master}}"

  LOGGER step "Cloning/Pulling hostapd (branch: $BRANCH)"
  if [[ ! -d "$REPO_DIR/.git" ]]; then
    if ! git clone --depth=1 --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"; then
      LOGGER warn "Branch '$BRANCH' not found; cloning default HEAD"
      git clone --depth=1 "$REPO_URL" "$REPO_DIR"
    fi
  else
    ( cd "$REPO_DIR" && git fetch --depth=1 origin "$BRANCH" || true
      git checkout "$BRANCH" 2>/dev/null || true
      git reset --hard "origin/$BRANCH" 2>/dev/null || git reset --hard origin/HEAD )
  fi

  pushd "$REPO_DIR/hostapd" >/dev/null
  cp -f defconfig .config

  # Enable the features required by your template (nl80211, 11n/ac, ACS)
  for flag in CONFIG_DRIVER_NL80211 CONFIG_LIBNL32 CONFIG_IEEE80211N CONFIG_IEEE80211AC CONFIG_ACS; do
    if grep -Eq "^(#\s*)?$flag" .config; then
      sed -i "s|^\s*#*\s*${flag}.*|${flag}=y|" .config
    elif ! grep -q "^$flag=y" .config; then
      echo "$flag=y" >> .config
    fi
  done

  LOGGER step "Compiling hostapd"
  make -j"$(nproc)"

  LOGGER step "Installing hostapd"
  sudo make install

  popd >/dev/null
  popd >/dev/null

  local bin_path
  bin_path="$(command -v hostapd || true)"
  LOGGER ok "hostapd installed at: ${bin_path:-<not found>}"
  LOGGER info "hostapd version: $(hostapd -v 2>/dev/null || echo 'unknown')"
}

_render_hostapd_conf_from_template() {
  local tpl="$ROOT_DIR/config/hostapd/hostapd.conf"
  local dst="/etc/hostapd/hostapd.conf"

  [[ -f "$tpl" ]] || { LOGGER error "Missing $tpl"; exit 1; }

  LOGGER step "Rendering hostapd config → $dst"
  sudo install -d -m 0755 /etc/hostapd

  # Variables expected by YOUR template
  export WIRELESS_IF WIRELESS_SSID WIRELESS_PASSWORD WIRELESS_COUNTRY

  if command -v envsubst >/dev/null 2>&1; then
    envsubst '$WIRELESS_IF$WIRELESS_SSID$WIRELESS_PASSWORD$WIRELESS_COUNTRY' < "$tpl" \
      | sudo tee "$dst" >/dev/null
  else
    # Fallback sed if envsubst is not available
    sudo sed \
      -e "s|\${WIRELESS_IF}|${WIRELESS_IF}|g" \
      -e "s|\${WIRELESS_SSID}|${WIRELESS_SSID}|g" \
      -e "s|\${WIRELESS_PASSWORD}|${WIRELESS_PASSWORD}|g" \
      -e "s|\${WIRELESS_COUNTRY}|${WIRELESS_COUNTRY}|g" \
      "$tpl" | sudo tee "$dst" >/dev/null
  fi

  # In bridge mode, we add the directive (without touching the template)
  if [[ "$NET_MODE" == "bridge" ]]; then
    if grep -q '^bridge=' "$dst"; then
      sudo sed -i "s|^bridge=.*|bridge=${BRIDGE_IF}|" "$dst"
    else
      echo "bridge=${BRIDGE_IF}" | sudo tee -a "$dst" >/dev/null
    fi
  fi

  sudo chmod 0644 "$dst"
  LOGGER ok "hostapd.conf rendered"
}

_install_unit_if_present() {
  local src="$ROOT_DIR/config/services/hostapd.service"
  local dst="/etc/systemd/system/hostapd.service"
  [[ -f "$src" ]] || { LOGGER info "No custom hostapd.service provided (skip)"; return 0; }

  LOGGER step "Installing systemd unit hostapd.service"
  if systemctl is-enabled hostapd 2>&1 | grep -q masked || { [ -L "$dst" ] && [[ "$(readlink -f "$dst")" == "/dev/null" ]]; }; then
    sudo systemctl stop hostapd 2>/dev/null || true
    sudo systemctl disable hostapd 2>/dev/null || true
    sudo systemctl unmask hostapd || true
    sudo rm -f "$dst" || true
  fi
  sudo install -m 0644 -T "$src" "$dst"

  # Point ExecStart to the correct binary
  local bin_path
  bin_path="$(command -v hostapd || echo /usr/local/sbin/hostapd)"
  sudo sed -i "s|^ExecStart=.*hostapd .*|ExecStart=${bin_path} -B /etc/hostapd/hostapd.conf|" "$dst"

  sudo systemctl daemon-reload
  LOGGER info "hostapd.service installed (enable/start handled by 080_services.sh)"
}

_test_config() {
  LOGGER step "Testing hostapd configuration (hostapd -t)"
  if ! sudo hostapd -t /etc/hostapd/hostapd.conf; then
    LOGGER error "hostapd config test failed"
    exit 1
  fi
  LOGGER ok "hostapd configuration is syntactically valid"
}

init_hostapd() {
  _load_env
  _rfkill_and_regdomain
  _build_install_hostapd
  _render_hostapd_conf_from_template
  _install_unit_if_present
  _test_config

  LOGGER ok "hostapd installed and configured from template"
  LOGGER info "Start later with: sudo systemctl start hostapd  (handled by 080_services.sh)"
}
