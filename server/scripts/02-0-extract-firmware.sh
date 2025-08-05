#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../lib/log.sh"

ZIP="$SCRIPT_DIR/../bin/FW_RT_AC88U_300438445149.zip"
TRX_DIR="RT-AC88U"
WORKDIR="$(mktemp -d)"
EXTRACTED_KO="$SCRIPT_DIR/../bin/dhd.ko"
EXTRACTED_BIN="$SCRIPT_DIR/../bin/brcmfmac4366c-pcie.bin.fromtrx"

section "Extract firmware"

if [[ ! -f "$ZIP" ]]; then
  error "Missing ASUS firmware ZIP: $ZIP"
  exit 1
fi

step "Unpacking $ZIP into temp dir"
7z x "$ZIP" -o"$WORKDIR" >/dev/null

TRX=$(find "$WORKDIR/$TRX_DIR" -name "*.trx" | head -n1)
if [[ ! -f "$TRX" ]]; then
  error "TRX not found in $TRX_DIR"
  rm -rf "$WORKDIR"; exit 1
fi

step "Extracting dhd.ko from TRX"
7z x "$TRX" "lib/modules/2.6.36.4brcmarm/kernel/drivers/net/dhd/dhd.ko" -o"$WORKDIR" >/dev/null

KO="$WORKDIR/lib/modules/2.6.36.4brcmarm/kernel/drivers/net/dhd/dhd.ko"
if [[ ! -f "$KO" ]]; then
  error "dhd.ko not found inside TRX"
  rm -rf "$WORKDIR"; exit 1
fi

cp "$KO" "$EXTRACTED_KO"
ok "dhd.ko extracted to $EXTRACTED_KO"

step "Looking for embedded firmware blob (dlarray_4366c0)"
OFFSET=$(binwalk -R $'\x00\xf2\x3e\xb8\x04\xf2' "$KO" | sed -n '4p' | cut -d: -f1 || true)
SIZE=$(readelf -s "$KO" | grep dlarray_4366c0 | awk '{print $3}' || true)

if [[ -z "$OFFSET" || -z "$SIZE" ]]; then
  warn "dlarray_4366c0 not found in dhd.ko – firmware blob not extracted"
else
  step "Extracting firmware blob via dd (offset=$OFFSET, size=$SIZE)"
  dd if="$KO" skip="$OFFSET" ibs=1 count="$SIZE" of="$EXTRACTED_BIN" status=none
  ok "Extracted firmware blob to $EXTRACTED_BIN"
fi

rm -rf "$WORKDIR"
summary "Done. You can manually test insmod or inspect blobs in ./bin/"
