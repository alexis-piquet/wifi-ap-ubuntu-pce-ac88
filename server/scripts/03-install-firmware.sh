#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../lib/log.sh"

FIRMWARE_DIR="/bin"
BIN_FILE="$FIRMWARE_DIR/brcmfmac4366c-pcie.bin"
TXT_FILE="$FIRMWARE_DIR/brcmfmac4366c-pcie.txt"

section "Broadcom 4366c Firmware Check"

step "Ensuring firmware directory exists"
sudo mkdir -p "$FIRMWARE_DIR"

# -- Remove invalid txt file if it's 0 byte
if [[ -f "$TXT_FILE" && ! -s "$TXT_FILE" ]]; then
  warn "Removing invalid or empty firmware TXT file"
  sudo rm -f "$TXT_FILE"
fi

# -- Download .bin if missing
if [[ ! -f "$BIN_FILE" ]]; then
  step "Downloading brcmfmac4366c-pcie.bin"
  if ! sudo wget -q -O "$BIN_FILE" "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/brcm/brcmfmac4366c-pcie.bin"; then
    error "Failed to download firmware binary"
    exit 1
  fi
  ok "Firmware BIN downloaded"
fi

# -- Download .txt if missing
if [[ ! -f "$TXT_FILE" ]]; then
  step "Downloading brcmfmac4366c-pcie.txt"
  if ! sudo wget -q -O "$TXT_FILE" "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/brcm/brcmfmac4366c-pcie.txt"; then
    error "Failed to download firmware TXT"
    exit 1
  fi
  ok "Firmware TXT downloaded"
fi

# -- Validate .txt is not empty
if [[ ! -s "$TXT_FILE" || $(stat -c%s "$TXT_FILE") -lt 32 ]]; then
  error "Firmware TXT file is invalid (too small or empty)"
  warn "You must extract a valid brcmfmac4366c-pcie.txt from the ASUS Windows driver"
  exit 1
fi

# -- Reload module
step "Reloading brcmfmac module"
sudo modprobe -r brcmfmac || true
sleep 1
sudo modprobe brcmfmac
ok "brcmfmac module reloaded"
