#!/usr/bin/env bash
set -euo pipefail

CURRENT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_PATH/../lib/utils.sh"
source_as "$CURRENT_PATH/../lib/logger.sh" "LOGGER"

init_firmware() {
  LOGGER info "Ensuring firmware directory exists"

  local SYSTEM_FIRMWARE_PATH="/lib/firmware/brcm"
  local BIN="brcmfmac4366c-pcie.bin"
  local LOCAL_BIN="$CURRENT_PATH/../bin/$BIN"
  local BIN_URL="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/brcm/$BIN"
  local TARGET="$SYSTEM_FIRMWARE_PATH/$BIN"

  sudo install -d -m 0755 "$SYSTEM_FIRMWARE_PATH"

  if [[ -f "$LOCAL_BIN" ]]; then
    LOGGER step "Installing local $BIN"
    sudo install -m 0644 "$LOCAL_BIN" "$TARGET"
  elif [[ ! -f "$TARGET" ]]; then
    LOGGER step "Downloading $BIN"
    if command -v curl >/dev/null 2>&1; then
      sudo sh -c "curl -fsSL '$BIN_URL' > '$TARGET.tmp'"
    else
      sudo sh -c "wget -qO '$TARGET.tmp' '$BIN_URL'"
    fi
    sudo mv "$TARGET.tmp" "$TARGET"
    LOGGER ok "$BIN downloaded"
  else
    LOGGER info "$BIN already present at $TARGET"
  fi

  LOGGER step "Reloading brcmfmac"
  if lsmod | grep -q '^brcmfmac'; then
    sudo modprobe -r brcmfmac || true
  fi
  sudo modprobe brcmfmac

  LOGGER ok "Firmware ready: $TARGET"
}
