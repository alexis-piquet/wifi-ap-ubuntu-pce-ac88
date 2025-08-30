#!/usr/bin/env bash
# shellcheck shell=bash

set -o errtrace

if [[ -z "${RED-}" ]]; then
  . "$(dirname "${BASH_SOURCE[0]}")/colors.sh"
fi

today="$(date +'%d-%m-%Y')"
: "${LOG_FILE:=logs/${today}.log}"
: "${LOG_LEVEL:=INFO}"
: "${TIMESTAMP_FMT:=%Y-%m-%d %H:%M:%S}"
: "${LOG_PREFIX:=}"
: "${LOG_ENABLE_TEE:=1}"

mkdir -p "$(dirname "$LOG_FILE")"

if [[ "${LOG_ENABLE_TEE}" = "1" && -z "${LOG_TEE_STARTED:-}" ]]; then
  exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)
  export LOG_TEE_STARTED=1
fi

_log_level_value() {
  case "$1" in
    DEBUG) echo 10 ;;
    INFO ) echo 20 ;;
    WARN ) echo 30 ;;
    ERROR) echo 40 ;;
    *    ) echo 20 ;;
  esac
}

log_set_level() {
  local lvl="${1^^}"
  case "$lvl" in DEBUG|INFO|WARN|ERROR) LOG_LEVEL="$lvl" ;; *) ;; esac
}

_log() {
  local level="$1"; shift
  local msg="$*"
  local ts; ts="$(date +"$TIMESTAMP_FMT")"

  local color prefix shown_level="$level"
  case "$level" in
    DEBUG) color="$DIM";    prefix="⟪DBG⟫" ;;
    INFO ) color="$CYAN";   prefix="ℹ"     ;;
    WARN ) color="$YELLOW"; prefix="⚠"     ;;
    ERROR) color="$RED";    prefix="✖"     ;;
    OK   ) color="$GREEN";  prefix="✔" ; shown_level="INFO" ;;
    STEP ) color="$BLUE";   prefix="➤" ; shown_level="INFO" ;;
    *    ) color="";        prefix="-" ;  shown_level="INFO" ;;
  esac

  if (( $(_log_level_value "$shown_level") >= $(_log_level_value "$LOG_LEVEL") )); then
    if [[ -n "$LOG_PREFIX" ]]; then
      printf "%b[%s] %s %s%s%b\n" "$color" "$ts" "$prefix" "$LOG_PREFIX" "$msg" "$NC"
    else
      printf "%b[%s] %s %s%b\n" "$color" "$ts" "$prefix" "$msg" "$NC"
    fi
  fi
}

debug() { _log DEBUG "$*"; }
info()  { _log INFO  "$*"; }
warn()  { _log WARN  "$*"; }
error() { _log ERROR "$*"; }
ok()    { _log OK    "$*"; }
step()  { _log STEP  "$*"; }

section() {
  local title="$*"
  printf "%b\n" "${BLUE}#--------------------[ ${title} ]--------------------#${NC}"
}

_log_on_error() {
  local ec=$?
  local src="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
  local line="${BASH_LINENO[0]:-0}"
  local cmd="${BASH_COMMAND:-?}"
  error "Command failed (exit=${ec}) at ${src}:${line} -> '${cmd}'"
  exit "$ec"
}

if [[ -z "${LOG_TRAP_SET:-}" ]]; then
  trap _log_on_error ERR
  export LOG_TRAP_SET=1
fi

log_with_prefix() {
  local tmp_prefix="$1"; shift
  local fn="$1"; shift
  ( LOG_PREFIX="${tmp_prefix}"; "$fn" "$@" )
}
