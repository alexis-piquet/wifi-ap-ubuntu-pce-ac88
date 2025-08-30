#!/usr/bin/env bash
set -euo pipefail

CURRENT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_PATH/../lib/utils.sh"

export LOG_NAMESPACE="[SCRIPTS][FIRMWARE]"
source_as "$CURRENT_PATH/../lib/logger.sh" "LOGGER"

init_firmware() {
  LOGGER info "Ensuring firmware directory exists"

  local SYSTEM_FIRMWARE_PATH="/lib/firmware/brcm"
  local BIN="brcmfmac4366c-pcie.bin"
  local CLM="brcmfmac4366c-pcie.clm_blob"
  local LOCAL_BIN="$CURRENT_PATH/../bin/$BIN"
  local LOCAL_CLM="$CURRENT_PATH/../bin/$CLM"
  local URL_BASE="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/brcm"

  sudo install -d -m 0755 "$SYSTEM_FIRMWARE_PATH"

  # --- BIN ---
  if [[ -f "$LOCAL_BIN" ]]; then
    LOGGER step "Installing local $BIN"
    sudo install -m 0644 "$LOCAL_BIN" "$SYSTEM_FIRMWARE_PATH/$BIN"
  else
    LOGGER step "Downloading $BIN"
    sudo sh -c "curl -fsSL '$URL_BASE/$BIN' > '$SYSTEM_FIRMWARE_PATH/$BIN.tmp' && mv '$SYSTEM_FIRMWARE_PATH/$BIN.tmp' '$SYSTEM_FIRMWARE_PATH/$BIN'"
    LOGGER ok "$BIN downloaded"
  fi

  # --- CLM_BLOB ---
  if [[ -f "$LOCAL_CLM" ]]; then
    LOGGER step "Installing local $CLM"
    sudo install -m 0644 "$LOCAL_CLM" "$SYSTEM_FIRMWARE_PATH/$CLM"
  else
    LOGGER step "Downloading $CLM"
    sudo sh -c "curl -fsSL '$URL_BASE/$CLM' > '$SYSTEM_FIRMWARE_PATH/$CLM.tmp' && mv '$SYSTEM_FIRMWARE_PATH/$CLM.tmp' '$SYSTEM_FIRMWARE_PATH/$CLM'"
    LOGGER ok "$CLM downloaded"
  fi

  # --- Reload driver ---
  LOGGER step "Reloading brcmfmac"
  if lsmod | grep -q '^brcmfmac'; then
    sudo modprobe -r brcmfmac || true
  fi
  sudo modprobe brcmfmac

  # --- Sanity checks ---
  if dmesg | tail -n 300 | grep -qi 'no clm_blob available'; then
    LOGGER warn "Driver still reports missing clm_blob; verify $SYSTEM_FIRMWARE_PATH/$CLM"
  fi

  if ! iw list 2>/dev/null | grep -q '^\s*\*\s*AP'; then
    LOGGER warn "Interface reports no AP support avec brcmfmac (BCM4366 souvent limité). Le mode AP peut échouer; dhd.ko est souvent requis."
  fi

  LOGGER ok "Firmware ready in $SYSTEM_FIRMWARE_PATH (check: dmesg | grep -i brcmfmac)"
}
