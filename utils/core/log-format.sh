#!/bin/sh
# utils/core/log-format.sh — Formatting + safety rails (POSIX sh)
# Author: deadhedd
# License: MIT
# shellcheck shell=sh
#
# Wrapper-only design target:
# - Never writes to stdout.
# - Safe to source multiple times (load-once).
# - Provides: sanitize, timestamp, level gating, line formatting.
#
# Config (env):
#   LOG_ASCII_ONLY=1|0   (default 1)
#   LOG_LEVEL=DEBUG|INFO|WARN|ERR (default INFO)
#   LOG_TIMESTAMP=1|0    (default 1)

(return 0 2>/dev/null) || { printf '%s\n' "ERR log-format.sh must be sourced, not executed" >&2; exit 2; }

if [ "${LOG_FORMAT_LOADED:-0}" -eq 1 ]; then
  return 0
fi
LOG_FORMAT_LOADED=1

: "${LOG_ASCII_ONLY:=1}"
: "${LOG_LEVEL:=INFO}"
: "${LOG_TIMESTAMP:=1}"

log_level__to_num() {
  case "${1:-INFO}" in
    DEBUG) printf '%s' 10 ;;
    INFO)  printf '%s' 20 ;;
    WARN)  printf '%s' 30 ;;
    ERR)   printf '%s' 40 ;;
    *)     printf '%s' 20 ;;
  esac
}

log_level__should() {
  want=$(log_level__to_num "${1:-INFO}")
  cur=$(log_level__to_num "${LOG_LEVEL:-INFO}")
  [ "$want" -ge "$cur" ]
}

log_fmt__ts() {
  if [ "${LOG_TIMESTAMP:-1}" -ne 0 ] 2>/dev/null; then
    date '+%Y-%m-%dT%H:%M:%S%z'
  else
    printf '%s' "-"
  fi
}

log_fmt__sanitize() {
  if [ "${LOG_ASCII_ONLY:-1}" -ne 0 ] 2>/dev/null; then
    # Keep: tab, LF, CR, space..~
    printf '%s' "$*" | LC_ALL=C tr -cd '\11\12\15\40-\176'
  else
    printf '%s' "$*"
  fi
}

log_fmt__line() {
  level=$1
  shift
  msg=$(log_fmt__sanitize "$*")
  ts=$(log_fmt__ts)
  # Structure: "<ts> <LEVEL> <msg>"
  printf '%s %s %s' "$ts" "$level" "$msg"
}
