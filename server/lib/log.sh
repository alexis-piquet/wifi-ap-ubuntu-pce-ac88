#!/usr/bin/env bash
# shellcheck shell=bash

# Enable error trapping for better debugging
set -o errtrace

# Load colors if not already loaded
if [[ -z "${RED-}" ]]; then
  # shellcheck source=lib/colors.sh
  . "$(dirname "${BASH_SOURCE[0]}")/colors.sh"
fi

# Generate log file name based on today's date (DD-MM-YYYY.log)
today="$(date +'%d-%m-%Y')"
LOG_FILE="${LOG_FILE:-logs/${today}.log}"     # One log file per day
LOG_LEVEL="${LOG_LEVEL:-INFO}"                # Default log level
TIMESTAMP_FMT="${TIMESTAMP_FMT:-%Y-%m-%d %H:%M:%S}"  # Timestamp format

# Ensure logs directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Redirect stdout and stderr to the log file if not already done
if [[ -z "${LOG_TEE_STARTED:-}" ]]; then
  exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)
  export LOG_TEE_STARTED=1
fi

# Internal: Convert log level names to numeric values for comparison
_level_value() {
  case "$1" in
    DEBUG) echo 10;;
    INFO)  echo 20;;
    WARN)  echo 30;;
    ERROR) echo 40;;
    *)     echo 20;;  # Default to INFO
  esac
}

# Core logging function
_log() {
  local level="$1"; shift
  local msg="$*"
  local ts; ts="$(date +"$TIMESTAMP_FMT")"

  local color prefix
  case "$level" in
    DEBUG ) color="$DIM";    prefix="⟪DBG⟫";;
    INFO  ) color="$CYAN";   prefix="ℹ";;
    WARN  ) color="$YELLOW"; prefix="⚠";;
    ERROR ) color="$RED";    prefix="✖";;
    OK    ) color="$GREEN";  prefix="✔"; level="INFO";;
    STEP  ) color="$BLUE";   prefix="➤"; level="INFO";;
    *     ) color="";        prefix="-"; level="INFO";;
  esac

  # Only display messages at or above the configured log level
  if (( $(_level_value "$level") >= $(_level_value "$LOG_LEVEL") )); then
    printf "%b[%s] %s %s%b\n" "$color" "$ts" "$prefix" "$msg" "$NC"
  fi
}

# Public log functions for each level
debug() { _log DEBUG "$*"; }
info()  { _log INFO  "$*"; }
warn()  { _log WARN  "$*"; }
error() { _log ERROR "$*"; }
ok()    { _log OK    "$*"; }
step()  { _log STEP  "$*"; }

# Print a section separator with title
section() {
  local title="$*"
  printf "%b\n" "${BOLD}${BLUE}#--------------------[ ${title} ]--------------------#${NC}"
}

# Global error handler for tracing failing commands
on_error() {
  local ec=$?
  error "Command failed (exit=$ec) at ${BASH_SOURCE[1]}:${BASH_LINENO[0]} -> '${BASH_COMMAND}'"
  exit "$ec"
}
trap on_error ERR
