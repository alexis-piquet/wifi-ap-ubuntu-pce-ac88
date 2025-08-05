#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../lib/log.sh"

FIRMWARE_DIR="/lib/firmware/brcm"
MODULES_DIR="/lib/modules/$(uname -r)/kernel/drivers/net/wireless"
DHD_MODULE_DEST="$MODULES_DIR/dhd.ko"

BIN_FILE="$FIRMWARE_DIR/brcmfmac4366c-pcie.bin"
TXT_FILE="$FIRMWARE_DIR/brcmfmac4366c-pcie.txt"

LOCAL_BIN="$SCRIPT_DIR/../bin/brcmfmac4366c-pcie.bin"
LOCAL_TXT="$SCRIPT_DIR/../bin/brcmfmac4366c-pcie.txt"
ASUS_FW_ZIP="$SCRIPT_DIR/../bin/FW_RT_AC88U_300438445149.zip"

section "Broadcom 4366c Firmware Setup"

step "Ensuring firmware directory exists"
sudo mkdir -p "$FIRMWARE_DIR"

# -- Copy local firmware if available
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

# -- Remove invalid .txt if empty
if [[ -f "$TXT_FILE" && ! -s "$TXT_FILE" ]]; then
  warn "Removing invalid or empty firmware TXT file"
  sudo rm -f "$TXT_FILE"
fi

# -- Download firmware if still missing
if [[ ! -f "$BIN_FILE" ]]; then
  step "Downloading brcmfmac4366c-pcie.bin"
  sudo wget -q -O "$BIN_FILE" "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/brcm/brcmfmac4366c-pcie.bin"
  ok "Firmware BIN downloaded"
fi

if [[ ! -f "$TXT_FILE" ]]; then
  step "Downloading brcmfmac4366c-pcie.txt"
  sudo wget -q -O "$TXT_FILE" "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/brcm/brcmfmac4366c-pcie.txt"
  ok "Firmware TXT downloaded"
fi

# -- Validate TXT content
if [[ ! -s "$TXT_FILE" || $(stat -c%s "$TXT_FILE") -lt 32 ]]; then
  warn "Firmware TXT file is missing or too small, skipping"
  warn "This may reduce available channels or cause regulatory limitations"
  sudo rm -f "$TXT_FILE"
fi

# -- Extract dhd.ko from ASUS firmware
if [[ -f "$ASUS_FW_ZIP" ]]; then
  step "Extracting dhd.ko from ASUS firmware ZIP"
  mkdir -p /tmp/asus_fw
  cp "$ASUS_FW_ZIP" /tmp/asus_fw/
  cd /tmp/asus_fw

  # Extract TRX
  7z x FW_RT_AC88U_300438445149.zip >/dev/null
  7z x RT-AC88U/RT-AC88U_*.trx lib/modules/2.6.36.4brcmarm/kernel/drivers/net/dhd/dhd.ko >/dev/null

  if [[ -f "lib/modules/2.6.36.4brcmarm/kernel/drivers/net/dhd/dhd.ko" ]]; then
    step "Copying dhd.ko to modules directory"
    sudo mkdir -p "$MODULES_DIR"
    sudo cp "lib/modules/2.6.36.4brcmarm/kernel/drivers/net/dhd/dhd.ko" "$DHD_MODULE_DEST"
    ok "dhd.ko extracted and installed"
  else
    error "dhd.ko not found after extraction"
    exit 1
  fi

  # Cleanup
  rm -rf /tmp/asus_fw
else
  warn "ASUS firmware ZIP not found, skipping dhd.ko extraction"
fi

# -- Unblock Wi-Fi if blocked
if rfkill list | grep -q "Soft blocked: yes"; then
  step "Unblocking Wi-Fi interfaces"
  sudo rfkill unblock all
  ok "Wi-Fi unblocked"
fi

# -- Reload Wi-Fi modules
step "Reloading Wi-Fi modules"
sudo modprobe -r brcmfmac || true
sudo modprobe -r dhd || true
sleep 1

if [[ -f "$DHD_MODULE_DEST" ]]; then
  sudo insmod "$DHD_MODULE_DEST"
  ok "dhd module inserted"
else
  sudo modprobe brcmfmac
  ok "brcmfmac module loaded"
fi
