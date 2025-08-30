#!/usr/bin/env bash
set -euo pipefail

CURRENT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_PATH/../lib/utils.sh"

export LOG_NAMESPACE="[SCRIPTS][HOSTAPD]"
source_as "$CURRENT_PATH/../lib/logger.sh" "LOGGER"

init_hostapd() {
  LOGGER info "Compiling and installing hostapd from source"
  export GIT_TERMINAL_PROMPT=0

  BUILD_DIR="$HOME/hostap_build"
  REPO_DIR="$BUILD_DIR/hostap"
  REPO_URL="${HOSTAPD_REPO_URL:-https://w1.fi/hostap.git}"  # <- par défaut officiel
  BRANCH="${HOSTAPD_BRANCH:-master}"

  mkdir -p "$BUILD_DIR"
  cd "$BUILD_DIR"

  LOGGER step "Checking hostap repo reachability"
  if ! git ls-remote --exit-code "$REPO_URL" &>/dev/null; then
    LOGGER error "Cannot reach repo: $REPO_URL. Set HOSTAPD_REPO_URL."
    return 1
  fi

  LOGGER step "Cloning hostap.git (if not already)"
  if [[ ! -d "$REPO_DIR/.git" ]]; then
    git clone --depth=1 --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
  else
    LOGGER info "hostap repo exists, pulling latest"
    (cd "$REPO_DIR" && git fetch --depth=1 origin "$BRANCH" && git checkout "$BRANCH" && git reset --hard "origin/$BRANCH")
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
  LOGGER info "Version: $(hostapd -v 2>/dev/null || echo 'unknown')"
}