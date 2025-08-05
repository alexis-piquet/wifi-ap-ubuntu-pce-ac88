#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/lib/log.sh"

section "COMPILE HOSTAPD"

step "Installing dependencies"
sudo apt -y install build-essential crda libssl-dev libnl-3-dev libnl-genl-3-dev libnl-route-3-dev pkg-config libnfnetlink-dev

cd ~
step "Cloning hostap repository"
git clone https://w1.fi/hostap.git || true

cd hostap/hostapd
git checkout hostap_2_3 || true
cp defconfig .config

step "Enabling features in .config"
sed -i 's/^#CONFIG_IEEE80211N=y/CONFIG_IEEE80211N=y/' .config
sed -i 's/^#CONFIG_IEEE80211AC=y/CONFIG_IEEE80211AC=y/' .config
sed -i 's/^#CONFIG_ACS=y/CONFIG_ACS=y/' .config
sed -i 's/^#CONFIG_DRIVER_NL80211=y/CONFIG_DRIVER_NL80211=y/' .config
sed -i 's/^#CONFIG_LIBNL32=y/CONFIG_LIBNL32=y/' .config

step "Compiling..."
make -j$(nproc)
sudo make install

ok "hostapd compiled and installed"
