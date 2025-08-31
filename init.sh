#!/bin/bash
set -euo pipefail

CURRENT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$CURRENT_PATH"

source    "./lib/utils.sh"

export LOG_NAMESPACE="[INIT]"

source_as "./lib/logger.sh"               "LOGGER"
source_as "./scripts/000_dependencies.sh" "SCRIPTS_000_DEPENDENCIES"
source_as "./scripts/010_env.sh"          "SCRIPTS_010_ENV"
source_as "./scripts/020_firmware.sh"     "SCRIPTS_020_FIRMWARE"
source_as "./scripts/030_network.sh"      "SCRIPTS_030_NETWORK"
source_as "./scripts/040_hostapd.sh"      "SCRIPTS_040_HOSTAPD"
source_as "./scripts/050_dnsmasq.sh"      "SCRIPTS_050_DNSMASQ"
source_as "./scripts/060_nat.sh"          "SCRIPTS_060_NAT"
source_as "./scripts/070_allowlist.sh"    "SCRIPTS_070_ALLOWLIST"
source_as "./scripts/080_services.sh"     "SCRIPTS_080_SERVICES"
source_as "./scripts/090_doctor.sh"       "SCRIPTS_090_DOCTOR"

init() {
  LOGGER info "Starting installation..."

  SCRIPTS_000_DEPENDENCIES init_dependencies
  SCRIPTS_010_ENV          init_env
  SCRIPTS_020_FIRMWARE     init_firmware
  SCRIPTS_030_NETWORK      init_network
  SCRIPTS_040_HOSTAPD      init_hostapd
  SCRIPTS_050_DNSMASQ      init_dnsmasq
  SCRIPTS_060_NAT          init_nat
  SCRIPTS_070_ALLOWLIST    init_allowlist
  SCRIPTS_080_SERVICES     init_services
  SCRIPTS_090_DOCTOR       init_doctor

  LOGGER ok "Installation complete. You can now run: ./start.sh"
}

init