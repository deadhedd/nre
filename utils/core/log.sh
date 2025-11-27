#!/bin/sh
# utils/core/log.sh — Shared logging helper for POSIX shell scripts.
# Author: deadhedd
# License: MIT

# This helper is intended to be sourced. Avoid redefining if already loaded.
if [ "${LOG_HELPER_LOADED:-0}" -eq 1 ] 2>/dev/null; then
  return 0 2>/dev/null || exit 0
fi
LOG_HELPER_LOADED=1

# Emit a timestamp in UTC when enabled. Default is on; set LOG_TIMESTAMP=0 to disable.
log__now() {
  if ! command -v date >/dev/null 2>&1; then
    return 1
  fi
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

# Sanitize messages when ASCII-only logs are required (default on).
log__sanitize() {
  if [ "${LOG_ASCII_ONLY:-1}" -ne 0 ]; then
    # Allow horizontal tab, LF, CR, and printable ASCII.
    printf '%s' "$*" | LC_ALL=C tr -cd '\11\12\15\40-\176'
  else
    printf '%s' "$*"
  fi
}

log__append_file() {
  line=$1
  log_file=${LOG_FILE:-}
  [ -n "$log_file" ] || return 0

  case "$log_file" in
    */*)
      dir=${log_file%/*}
      [ -n "$dir" ] && [ -d "$dir" ] || mkdir -p "$dir"
      ;;
  esac

  printf '%s\n' "$line" >>"$log_file"
}

log__emit() {
  level=$1
  stream=$2
  shift 2
  msg=$(log__sanitize "$*")

  if [ "${LOG_TIMESTAMP:-1}" -ne 0 ] && ts=$(log__now 2>/dev/null); then
    line="$ts $level $msg"
  else
    line="$level $msg"
  fi

  case "$stream" in
    stderr) printf '%s\n' "$line" >&2 ;;
    *) printf '%s\n' "$line" ;;
  esac

  log__append_file "$line"
}

log_info() { log__emit INFO stdout "$@"; }
log_warn() { log__emit WARN stderr "$@"; }
log_err()  { log__emit ERR stderr "$@"; }
log_debug() {
  if [ "${LOG_DEBUG:-0}" -ne 0 ]; then
    log__emit DEBUG stdout "$@"
  fi
}
