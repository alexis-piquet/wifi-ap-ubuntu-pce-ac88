#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../lib/log.sh"

section "COMPILE HOSTAPD"

BUILD_DIR="$HOME/hostap_build"
REPO_DIR="$BUILD_DIR/hostap"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

step "Cloning hostap.git (if not already)"
if [[ ! -d "$REPO_DIR" ]]; then
  git clone --depth=1 https://w1.fi/hostap.git "$REPO_DIR"
else
  info "hostap repository already exists"
fi

cd "$REPO_DIR/hostapd"
cp defconfig .config

step "Enabling nl80211 + ACS + 802.11n/ac"
for flag in CONFIG_DRIVER_NL80211 CONFIG_LIBNL32 CONFIG_IEEE80211N CONFIG_IEEE80211AC CONFIG_ACS; do
  if grep -Eq "^(#\s*)?$flag" .config; then
    sed -i "s|^\s*#*\s*${flag}.*|${flag}=y|" .config
  elif ! grep -q "^$flag=y" .config; then
    echo "$flag=y" >> .config
  fi
done

step "Building hostapd"
make -j"$(nproc)"

step "Installing hostapd"
sudo make install

ok "hostapd compiled and installed"
info "You can now run hostapd with your config. Try 'hostapd -v'."
