#!/usr/bin/env bash
set -euo pipefail

CURRENT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$CURRENT_PATH/.."

source "$ROOT_DIR/lib/utils.sh"
source_as "$ROOT_DIR/lib/logger.sh" "LOGGER"

init_firmware() {
  LOGGER info "Ensuring Broadcom firmware is present (brcmfmac4366c)"

  local FW_DIR="/lib/firmware/brcm"
  local BIN="brcmfmac4366c-pcie.bin"
  local TXT="brcmfmac4366c-pcie.txt"   # NVRAM board file (optional, if available locally)
  local LOCAL_BIN="$ROOT_DIR/bin/$BIN"
  local LOCAL_TXT="$ROOT_DIR/bin/$TXT"
  local BIN_URL="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/brcm/$BIN"
  local TARGET_BIN="$FW_DIR/$BIN"
  local TARGET_TXT="$FW_DIR/$TXT"

  sudo install -d -m 0755 "$FW_DIR"

  # --- .bin: priority to local, otherwise download ---
  if [[ -f "$LOCAL_BIN" ]]; then
    LOGGER step "Installing local $BIN"
    sudo install -m 0644 "$LOCAL_BIN" "$TARGET_BIN"
  elif [[ ! -f "$TARGET_BIN" ]]; then
    LOGGER step "Downloading $BIN from linux-firmware"
    if command -v curl >/dev/null 2>&1; then
      sudo sh -c "curl -fsSL '$BIN_URL' > '$TARGET_BIN.tmp'"
    else
      sudo sh -c "wget -qO '$TARGET_BIN.tmp' '$BIN_URL'"
    fi
    sudo mv "$TARGET_BIN.tmp" "$TARGET_BIN"
    LOGGER ok "$BIN installed"
  else
    LOGGER info "$BIN already present at $TARGET_BIN"
  fi

  # --- .txt: only if you have it locally (otherwise we don't fail) ---
  if [[ -s "$LOCAL_TXT" ]]; then
    LOGGER step "Installing local $TXT"
    sudo install -m 0644 "$LOCAL_TXT" "$TARGET_TXT"
  elif [[ -f "$TARGET_TXT" ]]; then
    LOGGER info "$TXT already present at $TARGET_TXT"
  else
    LOGGER warn "No $TXT provided — continuing (most setups work without a board-specific NVRAM file)."
  fi

  # --- Reload the module to take into account the new firmware ---
  LOGGER step "Reloading brcmfmac kernel module"
  if lsmod | grep -q '^brcmfmac'; then
    sudo modprobe -r brcmfmac || true
  fi
  sudo modprobe brcmfmac

  # Small best-effort check
  sleep 1
  if dmesg | grep -i -E 'brcmfmac|brcm' | tail -n 1 >/dev/null; then
    LOGGER info "dmesg (latest brcmfmac line): $(dmesg | grep -i brcmfmac | tail -n 1 || true)"
  fi

  # If the wifi interface appears, we indicate it
  local wl_if
  wl_if="$(iw dev 2>/dev/null | awk '$1=="Interface"{print $2; exit}' || true)"
  if [[ -n "$wl_if" ]]; then
    LOGGER ok "Firmware/driver loaded; wireless interface detected: $wl_if"
  else
    LOGGER warn "No wireless interface detected yet — this can still be OK; continue with next steps."
  fi
}
