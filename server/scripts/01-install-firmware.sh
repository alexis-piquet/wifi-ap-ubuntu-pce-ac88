#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../lib/log.sh"


section "INSTALL FIRMWARE"

step "Creating firmware directory"
sudo mkdir -p /lib/firmware/brcm

step "Downloading firmware files"
sudo wget -O /lib/firmware/brcm/brcmfmac4366c-pcie.bin "https://gist.github.com/picchietti/337029cf1946ff9e43b0f57aa75f6556/raw/.../brcmfmac4366c-pcie.bin"
sudo wget -O /lib/firmware/brcm/brcmfmac4366c-pcie.txt "https://gist.githubusercontent.com/.../brcmfmac4366c-pcie.txt"

ok "Firmware installed successfully"
info "Reboot required if this is the first setup"
