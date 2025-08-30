#!/usr/bin/env bash
set -euo pipefail

CURRENT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_PATH/../lib/utils.sh"

export LOG_NAMESPACE="[SCRIPTS][FIRMWARE]"
source_as "$CURRENT_PATH/../lib/log.sh" "LOGGER"

init() {
  LOGGER section "Ensuring firmware directory exists"

  SYSTEM_FIRMWARE_PATH="/lib/firmware/brcm"
  BIN_FILE="$SYSTEM_FIRMWARE_PATH/brcmfmac4366c-pcie.bin"
  LOCAL_BIN_PATH="$CURRENT_PATH/../bin/brcmfmac4366c-pcie.bin"

  sudo mkdir -p "$SYSTEM_FIRMWARE_PATH"

  if [[ -f "$LOCAL_BIN_PATH" ]]; then
    LOGGER step "Copying local BIN firmware"
    sudo cp "$LOCAL_BIN_PATH" "$BIN_FILE"
    LOGGER ok "Local BIN copied"
  elif [[ ! -f "$BIN_FILE" ]]; then
    LOGGER step "Downloading firmware BIN"
    sudo wget -q -O "$BIN_FILE" "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/brcm/brcmfmac4366c-pcie.bin"
    LOGGER ok "BIN firmware downloaded"
  fi

  LOGGER info "Firmware ready in $SYSTEM_FIRMWARE_PATH (check with dmesg | grep brcmfmac)"

  sudo modprobe -r brcmfmac
  sudo modprobe brcmfmac
}
