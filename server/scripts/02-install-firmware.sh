#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../lib/log.sh"

FIRMWARE_DIR="/lib/firmware/brcm"
MODULES_DIR="/lib/modules/$(uname -r)/kernel/drivers/net/wireless"
BIN_FILE="$FIRMWARE_DIR/brcmfmac4366c-pcie.bin"
TXT_FILE="$FIRMWARE_DIR/brcmfmac4366c-pcie.txt"

LOCAL_BIN="$SCRIPT_DIR/../bin/brcmfmac4366c-pcie.bin"
LOCAL_TXT="$SCRIPT_DIR/../bin/brcmfmac4366c-pcie.txt"

# ASUS firmware ZIP contents
ZIP_PATH="$SCRIPT_DIR/../bin/FW_RT_AC88U_300438445149.zip"
TRX_PATH="RT-AC88U/RT-AC88U_3.0.0.4_384_45149-g467037b.trx"
KO_PATH="lib/modules/2.6.36.4brcmarm/kernel/drivers/net/dhd/dhd.ko"
EXTRACTED_KO_LOCAL_PATH="$SCRIPT_DIR/../bin/dhd.ko"

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

# -- Warn about empty TXT but don't delete
if [[ -f "$TXT_FILE" && ! -s "$TXT_FILE" ]]; then
  warn "Firmware TXT file exists but is empty – leaving it in place"
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
if [[ -s "$TXT_FILE" && $(stat -c%s "$TXT_FILE") -lt 32 ]]; then
  warn "Firmware TXT file is very small (<32 bytes) – may cause limitations"
fi

# -- Extract dhd.ko from ASUS firmware (for reference only)
step "Extracting dhd.ko from ASUS firmware ZIP"

if [[ -f "$ZIP_PATH" ]]; then
  TMPDIR="$(mktemp -d)"
  pushd "$TMPDIR" > /dev/null

  7z x "$ZIP_PATH" >/dev/null
  7z x "$TRX_PATH" "$KO_PATH" >/dev/null || true

  if [[ -f "$KO_PATH" ]]; then
    cp "$KO_PATH" "$EXTRACTED_KO_LOCAL_PATH"
    ok "dhd.ko extracted to $EXTRACTED_KO_LOCAL_PATH (for reference only)"
  else
    warn "dhd.ko not found inside the ASUS firmware TRX"
  fi

  popd > /dev/null
  rm -rf "$TMPDIR"
else
  warn "ASUS firmware ZIP not found, skipping dhd.ko extraction"
fi

# -- Unblock Wi-Fi if needed
if rfkill list | grep -q "Soft blocked: yes"; then
  step "Unblocking Wi-Fi interfaces"
  sudo rfkill unblock all
  ok "Wi-Fi unblocked"
fi

# -- Reload modules (safely)
step "Reloading Wi-Fi modules"
sudo modprobe -r brcmfmac || true
sudo modprobe -r dhd || true
sleep 1

if [[ -f "$EXTRACTED_KO_LOCAL_PATH" ]]; then
  warn "Skipping insmod of $EXTRACTED_KO_LOCAL_PATH (not compatible with current kernel)"
  info "If you want to use this driver, compile it from source for kernel $(uname -r)"
else
  sudo modprobe brcmfmac
  ok "brcmfmac module loaded"
fi

summary "Firmware setup complete. Use 'iw phy' or 'dmesg' to verify the Wi-Fi driver."
