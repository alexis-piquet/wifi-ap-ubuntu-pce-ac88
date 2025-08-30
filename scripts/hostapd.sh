#!/usr/bin/env bash
set -euo pipefail

CURRENT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_PATH/../lib/utils.sh"

export LOG_NAMESPACE="[SCRIPTS][HOSTAPD]"
source_as "$CURRENT_PATH/../lib/log.sh" "LOGGER"

init() {
  LOGGER section "Compiling and installing hostapd from source"
  BUILD_DIR="$HOME/hostap_build"
  REPO_DIR="$BUILD_DIR/hostap"
  mkdir -p "$BUILD_DIR"
  cd "$BUILD_DIR"

  LOGGER step "Cloning hostap.git (if not already)"
  if [[ ! -d "$REPO_DIR" ]]; then
    git clone --depth=1 https://github.com/pritambaral/hostapd.git "$REPO_DIR"
  else
    LOGGER info "hostap repository already exists"
  fi

  cd "$REPO_DIR/hostapd"
  cp defconfig .config

  LOGGER step "Enabling nl80211 + ACS + 802.11n/ac"
  for flag in CONFIG_DRIVER_NL80211 CONFIG_LIBNL32 CONFIG_IEEE80211N CONFIG_IEEE80211AC CONFIG_ACS; do
    if grep -Eq "^(#\s*)?$flag" .config; then
      sed -i "s|^\s*#*\s*${flag}.*|${flag}=y|" .config
    elif ! grep -q "^$flag=y" .config; then
      echo "$flag=y" >> .config
    fi
  done

  LOGGER step "Building hostapd"
  make -j"$(nproc)"

  LOGGER step "Installing hostapd"
  sudo make install

  LOGGER ok "hostapd compiled and installed"
  LOGGER info "You can now run hostapd with your config. Try 'hostapd -v'."
}
