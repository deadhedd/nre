#!/bin/sh
# utils/lib/datetime.sh
# Author: deadhedd
# License: MIT
# shellcheck shell=sh
#
# Purpose:
# - Provide deterministic local-first date/time helpers
# - Select a supported date(1) backend once (BSD vs GNU)
# - Library-only: MUST be sourced (never executed)
#
# Integration rule:
# - As a sourced library, this file MUST NOT mutate the caller's shell options
#   (e.g., set -e / set -u) or global environment like PATH.
# - Callers (wrappers/leaf scripts) own strict-mode policy.
#
# Contract note:
# - This library is local-first. It MUST NOT expose UTC-oriented APIs.

# Must be sourced, not executed.
# POSIX pattern: `return` only works when sourced.
(dt__sourced_guard() { return 0; } ) 2>/dev/null || {
  printf '%s\n' "Error: datetime.sh is a library and must be sourced, not executed." >&2
  exit 2
}

dt_die() { printf '%s\n' "Error: $*" >&2; return 10; }
dt_need() { [ -n "${2-}" ] || dt_die "$1 is required"; }

# --------------------------------------------------------------------
# Date backend selection (one-time, deterministic)
# 1 = BSD/OpenBSD/macOS date (supports -j -f and -r)
# 2 = GNU/coreutils date (supports -d and -d @EPOCH)
# --------------------------------------------------------------------

DT_DATE_BACKEND=0

# Prefer well-known system locations without mutating PATH.
DT_DATE_BIN=""
for _dt_p in /usr/local/bin/date /usr/bin/date /bin/date; do
  if [ -x "$_dt_p" ]; then
    DT_DATE_BIN="$_dt_p"
    break
  fi
done

# Fall back to whatever the caller's PATH resolves.
if [ -z "$DT_DATE_BIN" ]; then
  DT_DATE_BIN=$(command -v date 2>/dev/null || true)
fi

[ -n "$DT_DATE_BIN" ] || { dt_die "date not found"; return 10; }

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

dt__detect_date_backend || { dt_die "no supported date backend (need BSD date or GNU date)"; return 10; }

# ------------------
# Date parsing/validation (local)
# ------------------

dt_is_ymd() {
  case "${1-}" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) return 0 ;;
    *) return 1 ;;
  esac
}

dt_check_ymd() {
  dt_need "date" "${1-}" || return $?
  d=$1
  dt_is_ymd "$d" || { dt_die "invalid date format (expected YYYY-MM-DD): $d"; return 10; }

  case "$DT_DATE_BACKEND" in
    1)
      "$DT_DATE_BIN" -j -f '%Y-%m-%d' "$d" '+%Y-%m-%d' >/dev/null 2>&1 \
        || { dt_die "invalid date: $d"; return 10; }
      ;;
    2)
      "$DT_DATE_BIN" -d "$d" '+%Y-%m-%d' >/dev/null 2>&1 \
        || { dt_die "invalid date: $d"; return 10; }
      ;;
    *)
      dt_die "internal: date backend not set"; return 10 ;;
  esac
}

dt_date_parts() {
  dt_need "date" "${1-}" || return $?
  dt_check_ymd "$1" || return $?
  y=${1%%-*}
  rest=${1#*-}
  m=${rest%%-*}
  d=${rest#*-}
  printf '%s %s %s\n' "$y" "$m" "$d"
}

dt_time_parts_hhmm() {
  dt_need "time" "${1-}" || return $?
  t=$1
  case "$t" in
    [0-9][0-9]:[0-9][0-9]) : ;;
    *) dt_die "invalid time format (expected HH:MM): $t"; return 10 ;;
  esac

  h=${t%%:*}
  m=${t#*:}
  # numeric range checks without external tools
  case "$h" in
    00|01|02|03|04|05|06|07|08|09|10|11|12|13|14|15|16|17|18|19|20|21|22|23) : ;;
    *) dt_die "invalid hour in time: $t"; return 10 ;;
  esac
  case "$m" in
    00|01|02|03|04|05|06|07|08|09|10|11|12|13|14|15|16|17|18|19|20|21|22|23|24|25|26|27|28|29|30|31|32|33|34|35|36|37|38|39|40|41|42|43|44|45|46|47|48|49|50|51|52|53|54|55|56|57|58|59) : ;;
    *) dt_die "invalid minute in time: $t"; return 10 ;;
  esac

  # strip leading zeros for arithmetic consumers (still strings)
  printf '%s %s\n' "${h#0}" "${m#0}"
}

# ------------------
# Clock (local-first)
# ------------------

dt_now_epoch() { "$DT_DATE_BIN" '+%s'; }
dt_now_local_iso() { "$DT_DATE_BIN" '+%Y-%m-%dT%H:%M:%S%z'; }
dt_now_local_iso_no_tz() { "$DT_DATE_BIN" '+%Y-%m-%dT%H:%M:%S'; }
dt_now_local_compact() { "$DT_DATE_BIN" '+%Y%m%dT%H%M%S'; }
dt_now_local_log_ts() { "$DT_DATE_BIN" '+%Y-%m-%d-%H%M%S'; }
dt_today_local() { "$DT_DATE_BIN" '+%Y-%m-%d'; }

dt_date_shift_days() {
  dt_need "date" "${1-}" || return $?
  dt_need "day offset" "${2-}" || return $?
  base=$1
  off=$2
  dt_check_ymd "$base" || return $?

  case "$DT_DATE_BACKEND" in
    1)
      # BSD: -v supports relative adjustments in local time.
      # Use -j (no set system clock) and -f (parse).
      "$DT_DATE_BIN" -j -f '%Y-%m-%d' "$base" -v"${off}"d '+%Y-%m-%d' 2>/dev/null \
        || { dt_die "failed to shift date by days: base=$base off=$off"; return 10; }
      ;;
    2)
      # GNU: date -d understands "YYYY-MM-DD +N day" in local time.
      "$DT_DATE_BIN" -d "$base ${off} day" '+%Y-%m-%d' 2>/dev/null \
        || { dt_die "failed to shift date by days: base=$base off=$off"; return 10; }
      ;;
    *)
      dt_die "internal: date backend not set"; return 10 ;;
  esac
}

dt_yesterday_local() { dt_date_shift_days "$(dt_today_local)" -1; }
dt_tomorrow_local()   { dt_date_shift_days "$(dt_today_local)"  1; }

# ------------------
# Epoch formatting (local)
# ------------------

dt_epoch_to_local_iso() {
  dt_need "epoch" "${1-}" || return $?
  case "$DT_DATE_BACKEND" in
    1) "$DT_DATE_BIN" -r "$1" '+%Y-%m-%dT%H:%M:%S%z' ;;
    2) "$DT_DATE_BIN" -d "@$1" '+%Y-%m-%dT%H:%M:%S%z' ;;
    *) dt_die "internal: date backend not set" ;;
  esac
}

dt_epoch_to_local_date() {
  dt_need "epoch" "${1-}" || return $?
  case "$DT_DATE_BACKEND" in
    1) "$DT_DATE_BIN" -r "$1" '+%Y-%m-%d' ;;
    2) "$DT_DATE_BIN" -d "@$1" '+%Y-%m-%d' ;;
    *) dt_die "internal: date backend not set" ;;
  esac
}
