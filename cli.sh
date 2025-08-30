#!/bin/bash
set -euo pipefail

CURRENT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$CURRENT_PATH"

source    "./lib/utils.sh"

export LOG_NAMESPACE="[CLI]"
source_as "./lib/logger.sh"             "LOGGER"
source_as "./scripts/dependencies.sh"   "SCRIPTS_DEPENDENCIES"
source_as "./scripts/env.sh"            "SCRIPTS_ENV"
source_as "./scripts/firmware.sh"       "SCRIPTS_FIRMWARE"
source_as "./scripts/hostapd.sh"        "SCRIPTS_HOSTAPD"
source_as "./scripts/network.sh"        "SCRIPTS_NETWORK"
source_as "./scripts/dnsmasq.sh"        "SCRIPTS_DNSMASQ"
source_as "./scripts/nat.sh"            "SCRIPTS_NAT"
source_as "./scripts/services.sh"       "SCRIPTS_SERVICES"
source_as "./scripts/allowlist.sh"      "SCRIPTS_ALLOWLIST"
source_as "./scripts/test_and_debug.sh" "SCRIPTS_TEST_AND_DEBUG"

unknown_command() {
  LOGGER error "Unknown command '$COMMAND'"
  usage
  exit 1
}

initialize() {
  LOGGER info "Starting installation..."

  SCRIPTS_DEPENDENCIES init_dependencies
  SCRIPTS_ENV init_env
  SCRIPTS_FIRMWARE init_firmware
  SCRIPTS_HOSTAPD init_hostapd
  SCRIPTS_NETWORK init_network
  SCRIPTS_DNSMASQ init_dnsmasq
  SCRIPTS_NAT init_nat
  SCRIPTS_SERVICES init_services
  SCRIPTS_ALLOWLIST init_allowlist
  SCRIPTS_TEST_AND_DEBUG init_test_and_debug

  LOGGER ok "Installation complete. You can now run: ./start.sh"
}

while getopts "hc:" opt; do
  case $opt in
    c) CONFIG_FILE="$OPTARG" ;;
    *) LOGGER error "Invalid option: -$OPTARG"; usage ;;
  esac
done
shift $((OPTIND -1))

COMMAND=$1 || true
shift || true

if [[ -z "${COMMAND:-}" ]]; then
  LOGGER error "No command provided."
  usage
fi

case "$COMMAND" in
  init         ) initialize "$@" ;;
  start        ) LOGGER step "Starting..."; start "$@" ;;
  *            ) unknown_command ;;
esac
