#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../lib/log.sh"

FIRMWARE_DIR="/lib/firmware/brcm"
BIN_FILE="$FIRMWARE_DIR/brcmfmac4366c-pcie.bin"
TXT_FILE="$FIRMWARE_DIR/brcmfmac4366c-pcie.txt"
LOCAL_BIN="$SCRIPT_DIR/../bin/brcmfmac4366c-pcie.bin"
LOCAL_TXT="$SCRIPT_DIR/../bin/brcmfmac4366c-pcie.txt"

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

if [[ -f "$LOCAL_TXT" ]]; then
  step "Copying local TXT firmware"
  sudo cp "$LOCAL_TXT" "$TXT_FILE"
  ok "Local TXT copied"
elif [[ ! -f "$TXT_FILE" ]]; then
  step "Downloading firmware TXT"
  sudo wget -q -O "$TXT_FILE" "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/brcm/brcmfmac4366c-pcie.txt"
  ok "TXT firmware downloaded"
fi

if [[ -s "$TXT_FILE" && $(stat -c%s "$TXT_FILE") -lt 32 ]]; then
  warn "TXT firmware is suspiciously small (<32B). Check content."
fi

summary "Firmware ready in $FIRMWARE_DIR (check with 'dmesg | grep brcmfmac')"
