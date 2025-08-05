#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../lib/log.sh"

FIRMWARE_DIR="/lib/firmware/brcm"
BIN_FILE="$FIRMWARE_DIR/brcmfmac4366c-pcie.bin"
TXT_FILE="$FIRMWARE_DIR/brcmfmac4366c-pcie.txt"

LOCAL_BIN="$SCRIPT_DIR/../bin/brcmfmac4366c-pcie.bin"
LOCAL_TXT="$SCRIPT_DIR/../bin/brcmfmac4366c-pcie.txt"

section "Broadcom 4366c Firmware Check"

step "Ensuring firmware directory exists"
sudo mkdir -p "$FIRMWARE_DIR"

# Copier les fichiers locaux si disponibles
if [[ -f "$LOCAL_BIN" ]]; then
  step "Copying local BIN firmware"
  sudo cp "$LOCAL_BIN" "$BIN_FILE"
  ok "BIN firmware copied"
fi

if [[ -f "$LOCAL_TXT" ]]; then
  step "Copying local TXT firmware"
  sudo cp "$LOCAL_TXT" "$TXT_FILE"
  ok "TXT firmware copied"
fi

# -- Remove invalid txt file if it's 0 byte
if [[ -f "$TXT_FILE" && ! -s "$TXT_FILE" ]]; then
  warn "Removing invalid or empty firmware TXT file"
  sudo rm -f "$TXT_FILE"
fi

# Télécharger seulement si toujours manquant
if [[ ! -f "$BIN_FILE" ]]; then
  step "Downloading brcmfmac4366c-pcie.bin"
  if ! sudo wget -q -O "$BIN_FILE" "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/brcm/brcmfmac4366c-pcie.bin"; then
    error "Failed to download firmware binary"
    exit 1
  fi
  ok "Firmware BIN downloaded"
fi

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
