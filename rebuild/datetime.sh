#!/bin/sh
# utils/core/datetime.sh
# Author: deadhedd
# License: MIT
# shellcheck shell=sh

set -eu
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

# Refuse execution; must be sourced.
case "${0##*/}" in
  datetime.sh)
    printf '%s\n' "Error: datetime.sh is a library and must be sourced, not executed." >&2
    exit 10
    ;;
esac

dt_die() { printf '%s\n' "Error: $*" >&2; exit 10; }
dt_need() { [ -n "${2-}" ] || dt_die "$1 is required"; }

# --------------------------------------------------------------------
# Date backend selection (one-time, deterministic)
# 1 = BSD/OpenBSD/macOS date (supports -j -f and -r)
# 2 = GNU/coreutils date (supports -d and -d @EPOCH)
# --------------------------------------------------------------------

DT_DATE_BACKEND=0
DT_DATE_BIN=$(command -v date 2>/dev/null || true)
[ -n "$DT_DATE_BIN" ] || dt_die "date not found in PATH"

dt__detect_date_backend() {
  if "$DT_DATE_BIN" -j -f '%Y-%m-%d' '2000-01-01' '+%s' >/dev/null 2>&1 \
     && "$DT_DATE_BIN" -r 0 '+%Y-%m-%d' >/dev/null 2>&1; then
    DT_DATE_BACKEND=1
    return 0
  fi

  if "$DT_DATE_BIN" -d '2000-01-01 00:00:00' '+%s' >/dev/null 2>&1 \
     && "$DT_DATE_BIN" -d '@0' '+%Y-%m-%d' >/dev/null 2>&1; then
    DT_DATE_BACKEND=2
    return 0
  fi

  DT_DATE_BACKEND=0
  return 1
}

dt__detect_date_backend || dt_die "no supported date backend (need BSD date or GNU date)"

# ------------------
# Clock (local-first)
# ------------------

dt_now_epoch() {
  "$DT_DATE_BIN" '+%s'
}

dt_now_local_iso() {
  "$DT_DATE_BIN" '+%Y-%m-%dT%H:%M:%S%z'
}

dt_now_local_iso_no_tz() {
  "$DT_DATE_BIN" '+%Y-%m-%dT%H:%M:%S'
}

dt_now_local_compact() {
  "$DT_DATE_BIN" '+%Y%m%dT%H%M%S'
}

dt_today_local() {
  "$DT_DATE_BIN" '+%Y-%m-%d'
}

# ------------------
# Epoch formatting (local)
# ------------------

dt_epoch_to_local_iso() {
  dt_need "epoch" "${1-}"
  case "$DT_DATE_BACKEND" in
    1) "$DT_DATE_BIN" -r "$1" '+%Y-%m-%dT%H:%M:%S%z' ;;
    2) "$DT_DATE_BIN" -d "@$1" '+%Y-%m-%dT%H:%M:%S%z' ;;
    *) dt_die "internal: date backend not set" ;;
  esac
}

dt_epoch_to_local_date() {
  dt_need "epoch" "${1-}"
  case "$DT_DATE_BACKEND" in
    1) "$DT_DATE_BIN" -r "$1" '+%Y-%m-%d' ;;
    2) "$DT_DATE_BIN" -d "@$1" '+%Y-%m-%d' ;;
    *) dt_die "internal: date backend not set" ;;
  esac
}

# ------------------
# UTC → epoch (API boundary only)
# ------------------

dt_utc_iso_z_to_epoch() {
  # Accepts: YYYY-MM-DDTHH:MM:SSZ  (also tolerates a space instead of T)
  dt_need "utc timestamp" "${1-}"

  s=$1
  s=$(printf '%s' "$s" | tr ' ' 'T')

  case "$s" in
    *Z) ;;
    *) dt_die "not a UTC Z timestamp: $s" ;;
  esac

  case "$DT_DATE_BACKEND" in
    1)
      # BSD: -u forces UTC interpretation/output for parse
      "$DT_DATE_BIN" -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$s" '+%s' 2>/dev/null \
        || dt_die "failed to parse UTC timestamp: $s"
      ;;
    2)
      # GNU: Z is understood; be explicit about UTC
      "$DT_DATE_BIN" -u -d "$s" '+%s' 2>/dev/null \
        || dt_die "failed to parse UTC timestamp: $s"
      ;;
    *)
      dt_die "internal: date backend not set"
      ;;
  esac
}
