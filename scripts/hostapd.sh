#!/usr/bin/env bash
set -euo pipefail

CURRENT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_PATH/../lib/utils.sh"
source_as "$CURRENT_PATH/../lib/logger.sh" "LOGGER"

init_hostapd() {
  LOGGER info "Compiling and installing hostapd from source"
  export GIT_TERMINAL_PROMPT=0

  BUILD_DIR="$HOME/hostap_build"
  REPO_DIR="$BUILD_DIR/hostap"
  REPO_URL="${HOSTAPD_REPO_URL:-https://w1.fi/hostap.git}"

  mkdir -p "$BUILD_DIR"
  cd "$BUILD_DIR"

  LOGGER step "Checking hostap repo reachability"
  if ! git ls-remote --exit-code "$REPO_URL" &>/dev/null; then
    LOGGER error "Cannot reach repo: $REPO_URL. Set HOSTAPD_REPO_URL."
    return 1
  fi

  # 🔎 détecte la branche par défaut du remote (HEAD)
  DEFAULT_BRANCH="$(git ls-remote --symref "$REPO_URL" HEAD \
    | awk '/^ref:/ { sub("refs/heads/","",$2); print $2 }')"
  BRANCH="${HOSTAPD_BRANCH:-${DEFAULT_BRANCH:-main}}"

  LOGGER step "Cloning hostap.git (branch: $BRANCH)"
  if [[ ! -d "$REPO_DIR/.git" ]]; then
    if ! git clone --depth=1 --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"; then
      LOGGER warn "Branch '$BRANCH' not found; cloning default branch instead"
      git clone --depth=1 "$REPO_URL" "$REPO_DIR"
    fi
  else
    LOGGER info "hostap repo exists, pulling latest"
    (
      cd "$REPO_DIR"
      git fetch --depth=1 origin "$BRANCH" || true
      git checkout "$BRANCH" 2>/dev/null || true
      git reset --hard "origin/$BRANCH" 2>/dev/null || git reset --hard origin/HEAD
    )
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
