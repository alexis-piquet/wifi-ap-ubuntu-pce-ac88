#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../lib/log.sh"

FIRMWARE_DIR="/lib/firmware/brcm"
BIN_FILE="$FIRMWARE_DIR/brcmfmac4366c-pcie.bin"
LOCAL_BIN="$SCRIPT_DIR/../bin/brcmfmac4366c-pcie.bin"

section "Install Firmware"

step "Ensuring firmware directory exists"
sudo mkdir -p "$FIRMWARE_DIR"

if [[ -f "$LOCAL_BIN" ]]; then
  step "Copying local BIN firmware"
  sudo cp "$LOCAL_BIN" "$BIN_FILE"
  ok "Local BIN copied"
elif [[ ! -f "$BIN_FILE" ]]; then
  step "Downloading firmware BIN"
  sudo wget -q -O "$BIN_FILE" "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/brcm/brcmfmac4366c-pcie.bin"
  ok "BIN firmware downloaded"
fi

info "Firmware ready in $FIRMWARE_DIR (check with dmesg | grep brcmfmac)"

sudo modprobe -r brcmfmac
sudo modprobe brcmfmac