#!/bin/sh
# engine/lib/datetime.sh
# Author: deadhedd
# License: MIT
# shellcheck shell=sh
#
# Purpose:
# - Provide deterministic local-first date/time helpers
# - Provide date-space arithmetic via POSIX awk (no date(1) backend detection)
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
# Date tool discovery + shared awk date arithmetic primitives
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

dt__awk_common='
function floor(x) {
  if (x >= 0) return int(x)
  return int(x) - (x == int(x) ? 0 : 1)
}
function mod(a, b) {
  if (b == 0) return 0
  return a - b * floor(a / b)
}
function days_from_civil(y, m, d, era, yoe, doy, doe) {
  y -= (m <= 2) ? 1 : 0
  era = y >= 0 ? floor(y / 400) : floor((y - 399) / 400)
  yoe = y - era * 400
  m = (m + 9) % 12
  doy = floor((153 * m + 2) / 5) + d - 1
  doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
}
function civil_from_days(z, res, era, doe, yoe, doy, mp, y, m, d) {
  z += 719468
  era = z >= 0 ? floor(z / 146097) : floor((z - 146096) / 146097)
  doe = z - era * 146097
  yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
  y = yoe + era * 400
  doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
  mp = floor((5 * doy + 2) / 153)
  d = doy - floor((153 * mp + 2) / 5) + 1
  m = mp + 3
  if (m > 12) { m -= 12; y += 1 }
  res["y"] = y; res["m"] = m; res["d"] = d
}
function verify_ymd(y, m, d, tmp) {
  if (m < 1 || m > 12 || d < 1 || d > 31) return 0
  civil_from_days(days_from_civil(y, m, d), tmp)
  return (tmp["y"] == y && tmp["m"] == m && tmp["d"] == d)
}
'

dt__run_awk() {
  script=$1
  shift
  # POSIX: feed program on stdin, use -f -
  printf '%s\n%s\n' "$dt__awk_common" "$script" | awk "$@" -f -
}

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

  y=${d%%-*}
  rest=${d#*-}
  m=${rest%%-*}
  day=${rest#*-}

  dt__run_awk 'BEGIN {
    y = year + 0; m = month + 0; d = day + 0
    if (!verify_ymd(y, m, d, tmp)) exit 1
  }' -v year="$y" -v month="$m" -v day="$day" >/dev/null 2>&1 \
    || { dt_die "invalid date: $d"; return 10; }
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

dt_month_name_en() {
  # dt_month_name_en <MM>
  # Prints English month name for 01..12. Unknown input is printed verbatim.
  case "${1-}" in
    01) printf 'January' ;;
    02) printf 'February' ;;
    03) printf 'March' ;;
    04) printf 'April' ;;
    05) printf 'May' ;;
    06) printf 'June' ;;
    07) printf 'July' ;;
    08) printf 'August' ;;
    09) printf 'September' ;;
    10) printf 'October' ;;
    11) printf 'November' ;;
    12) printf 'December' ;;
    *)  printf '%s' "${1-}" ;;
  esac
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

  case "$off" in
    +[0-9]*|-[0-9]*|[0-9]*) : ;;
    *) dt_die "failed to shift date by days: base=$base off=$off"; return 10 ;;
  esac

  y=${base%%-*}
  rest=${base#*-}
  m=${rest%%-*}
  d=${rest#*-}

  dt__run_awk 'BEGIN {
    y = year + 0; m = month + 0; d = day + 0; off = delta + 0
    if (!verify_ymd(y, m, d, tmp)) exit 1
    z = days_from_civil(y, m, d) + off
    civil_from_days(z, out)
    printf "%04d-%02d-%02d\n", out["y"], out["m"], out["d"]
  }' -v year="$y" -v month="$m" -v day="$d" -v delta="$off" \
    || { dt_die "failed to shift date by days: base=$base off=$off"; return 10; }
}

dt_yesterday_local() { dt_date_shift_days "$(dt_today_local)" -1; }
dt_tomorrow_local()   { dt_date_shift_days "$(dt_today_local)"  1; }

# ------------------
# Epoch formatting (local)
# ------------------

dt_epoch_to_local_pretty() {
  dt_need "epoch" "${1-}" || return $?
  case "$DT_DATE_BACKEND" in
    1) "$DT_DATE_BIN" -r "$1" '+%Y-%m-%d %H:%M' ;;
    2) "$DT_DATE_BIN" -d "@$1" '+%Y-%m-%d %H:%M' ;;
    *) dt_die "internal: date backend not set" ;;
  esac
}

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
