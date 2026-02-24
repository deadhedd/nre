#!/bin/sh
# utils/lib/periods.sh
# Author: deadhedd
# License: MIT
# shellcheck shell=sh
#
# Purpose:
# - Period/tag helpers for notes (week/month/quarter/year tags, navigation tags)
# - Local-first: accepts/produces local calendar dates (YYYY-MM-DD) and tags
# - Library-only: MUST be sourced (never executed)
#
# Integration rule:
# - As a sourced library, this file MUST NOT mutate the caller's shell options
#   (e.g., set -e / set -u) or global environment like PATH.
# - Callers (wrappers/leaf scripts) own strict-mode policy.
#
# Dependency:
# - Requires datetime.sh (dt_today_local, dt_date_shift_days, dt_check_ymd, dt_date_parts)

# Must be sourced, not executed.
(pr__sourced_guard() { return 0; } ) 2>/dev/null || {
  printf '%s\n' "Error: periods.sh is a library and must be sourced, not executed." >&2
  exit 2
}

pr_die() { printf '%s\n' "Error: $*" >&2; return 10; }
pr_need() { [ -n "${2-}" ] || pr_die "$1 is required"; }

pr__need_datetime() {
  command -v dt_today_local >/dev/null 2>&1 || { pr_die "datetime.sh not loaded (missing dt_today_local)"; return 10; }
  command -v dt_date_shift_days >/dev/null 2>&1 || { pr_die "datetime.sh not loaded (missing dt_date_shift_days)"; return 10; }
  command -v dt_check_ymd >/dev/null 2>&1 || { pr_die "datetime.sh not loaded (missing dt_check_ymd)"; return 10; }
}

awk_common='
function floor(x) {
  if (x >= 0) {
    return int(x)
  }
  return int(x) - (x == int(x) ? 0 : 1)
}

function mod(a, b) {
  if (b == 0) {
    return 0
  }
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
  if (m > 12) {
    m -= 12
    y += 1
  }
  res["y"] = y
  res["m"] = m
  res["d"] = d
  res["doy"] = doy + 1
}

function verify_ymd(y, m, d, tmp) {
  if (m < 1 || m > 12 || d < 1 || d > 31) {
    return 0
  }
  civil_from_days(days_from_civil(y, m, d), tmp)
  return (tmp["y"] == y && tmp["m"] == m && tmp["d"] == d)
}

function weekday_from_days(z) {
  # Monday = 0, Sunday = 6
  return mod(z + 3, 7)
}

function day_of_year(y, m, d, days, ml, i) {
  ml[1] = 31
  ml[2] = 28
  ml[3] = 31
  ml[4] = 30
  ml[5] = 31
  ml[6] = 30
  ml[7] = 31
  ml[8] = 31
  ml[9] = 30
  ml[10] = 31
  ml[11] = 30
  ml[12] = 31
  if (is_leap_year(y)) {
    ml[2] = 29
  }
  days = 0
  for (i = 1; i < m; i++) {
    days += ml[i]
  }
  return days + d
}

function is_leap_year(y) {
  if ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0) {
    return 1
  }
  return 0
}

function iso_weeks_in_year(y, weekday_jan1) {
  weekday_jan1 = weekday_from_days(days_from_civil(y, 1, 1))
  if (weekday_jan1 == 3 || (weekday_jan1 == 2 && is_leap_year(y))) {
    return 53
  }
  return 52
}

function iso_week_from_days(z, out, tmp, doy, iso_week, iso_year, weeks, wd) {
  civil_from_days(z, tmp)
  iso_year = tmp["y"]
  wd = weekday_from_days(z)
  doy = day_of_year(tmp["y"], tmp["m"], tmp["d"])
  iso_week = floor((doy - wd + 10) / 7)
  if (iso_week < 1) {
    iso_year -= 1
    iso_week = iso_weeks_in_year(iso_year)
  } else {
    weeks = iso_weeks_in_year(iso_year)
    if (iso_week > weeks) {
      iso_year += 1
      iso_week = 1
    }
  }
  out["year"] = iso_year
  out["week"] = iso_week
}
'

pr__coerce_month_to_decimal() {
  month=${1:-}

  if [ -z "$month" ]; then
    printf '%s\n' 0
    return
  fi

  month=$(expr "$month" + 0)
  printf '%s\n' "$month"
}

pr_year_current() { pr__need_datetime || return $?; dt_date_parts "$(dt_today_local)" | awk '{print $1}'; }
pr_year_prev() { y=$(pr_year_current) || return $?; printf '%s\n' $(( y - 1 )); }
pr_year_next() { y=$(pr_year_current) || return $?; printf '%s\n' $(( y + 1 )); }

pr_quarter_of_month() {
  m=${1:-}
  [ -n "$m" ] || { pr_die "month is required"; return 10; }
  m=$(pr__coerce_month_to_decimal "$m")
  printf '%s\n' $(( (m + 2) / 3 ))
}

pr_quarter_tag() {
  pr__need_datetime || return $?
  set -- $(dt_date_parts "$(dt_today_local)") || return $?
  y=$1; m=$2
  q=$(pr_quarter_of_month "$m") || return $?
  printf 'Q%s-%s\n' "$q" "$y"
}

pr_quarter_tag_iso() {
  pr__need_datetime || return $?
  set -- $(dt_date_parts "$(dt_today_local)") || return $?
  y=$1; m=$2
  q=$(pr_quarter_of_month "$m") || return $?
  printf '%s-Q%s\n' "$y" "$q"
}

pr_today() { pr__need_datetime || return $?; dt_today_local; }
pr_yesterday() { pr__need_datetime || return $?; dt_yesterday_local; }
pr_tomorrow() { pr__need_datetime || return $?; dt_tomorrow_local; }

pr_local_iso_timestamp() { pr__need_datetime || return $?; dt_now_local_iso; }

pr_date_parts() { pr__need_datetime || return $?; dt_date_parts "${1:-$(dt_today_local)}"; }

pr__date_parts_strict() {
  pr__need_datetime || return $?
  pr_need "date" "${1:-}" || return $?
  dt_check_ymd "$1" || return $?
  dt_date_parts "$1"
}

pr_time_parts_hhmm() {
  if [ -z "${1:-}" ]; then
    pr_die "time is required"
    return 10
  fi

  # Prefer datetime's validator if present.
  command -v dt_time_parts_hhmm >/dev/null 2>&1 || { pr_die "datetime.sh not loaded (missing dt_time_parts_hhmm)"; return 10; }
  dt_time_parts_hhmm "$1"
}

pr_month_tag() {
  pr__need_datetime || return $?
  if [ "${1:-}" ]; then
    case "$1" in
      ????-??)
        printf '%s\n' "$1"
        ;;
      ????-??-??)
        if parts=$(pr__date_parts_strict "$1"); then
          set -- $parts
          printf '%04d-%02d\n' "$1" "$2"
          return 0
        fi
        return 1
        ;;
      *)
        return 1
        ;;
    esac
  else
    set -- $(dt_date_parts "$(dt_today_local)") || return $?
    printf '%04d-%02d\n' "$1" "$2"
  fi
}

pr_month_tag_current() { pr_month_tag; }

pr__add_months() {
  base_year=$1
  base_month=$2
  delta=$3
  base_year=$(expr "$base_year" + 0)
  base_month=$(expr "$base_month" + 0)
  delta=$(expr "$delta" + 0)
  total=$(( base_year * 12 + base_month - 1 + delta ))
  new_year=$(( total / 12 ))
  new_month=$(( total % 12 + 1 ))
  printf '%s %s\n' "$new_year" "$new_month"
}

pr_month_tag_prev() {
  pr__need_datetime || return $?
  set -- $(dt_date_parts "$(dt_today_local)") || return $?
  set -- $(pr__add_months "$1" "$2" -1)
  printf '%04d-%02d\n' "$1" "$2"
}

pr_month_tag_next() {
  pr__need_datetime || return $?
  set -- $(dt_date_parts "$(dt_today_local)") || return $?
  set -- $(pr__add_months "$1" "$2" 1)
  printf '%04d-%02d\n' "$1" "$2"
}

pr__run_awk() {
  script=$1
  shift
  printf '%s\n%s\n' "$awk_common" "$script" | awk "$@" -f -
}

pr_weekday_name_for_index() {
  case "$1" in
    0) printf 'Monday\n' ;;
    1) printf 'Tuesday\n' ;;
    2) printf 'Wednesday\n' ;;
    3) printf 'Thursday\n' ;;
    4) printf 'Friday\n' ;;
    5) printf 'Saturday\n' ;;
    6) printf 'Sunday\n' ;;
    *) return 1 ;;
  esac
}

pr_weekday_index_for_date() {
  parts=$(pr__date_parts_strict "$1") || return 1
  set -- $parts
  pr__run_awk 'BEGIN {
    y = year + 0
    m = month + 0
    d = day + 0
    if (!verify_ymd(y, m, d, tmp)) exit 1
    idx = weekday_from_days(days_from_civil(y, m, d))
    printf "%d\n", idx
  }' -v year="$1" -v month="$2" -v day="$3"
}

pr_week_tag() {
  pr__need_datetime || return $?
  if [ -n "${1:-}" ]; then
    parts=$(pr__date_parts_strict "$1") || return 1
  else
    parts=$(dt_date_parts "$(dt_today_local)") || return 1
  fi
  set -- $parts
  pr__run_awk 'BEGIN {
    y = year + 0
    m = month + 0
    d = day + 0
    if (!verify_ymd(y, m, d, tmp)) exit 1
    z = days_from_civil(y, m, d)
    iso_week_from_days(z, out, tmp2)
    printf "%04d-W%02d\n", out["year"], out["week"]
  }' -v year="$1" -v month="$2" -v day="$3"
}

pr_week_tag_current() { pr_week_tag; }

pr_week_tag_prev() {
  pr__need_datetime || return $?
  d=$(dt_date_shift_days "$(dt_today_local)" -7) || return $?
  pr_week_tag "$d"
}

pr_week_tag_next() {
  pr__need_datetime || return $?
  d=$(dt_date_shift_days "$(dt_today_local)" 7) || return $?
  pr_week_tag "$d"
}

pr_week_nav_tags_for_date() {
  pr__need_datetime || return $?
  pr_need "date" "${1:-}" || return $?
  dt_check_ymd "$1" || return $?
  prev=$(dt_date_shift_days "$1" -7) || return $?
  next=$(dt_date_shift_days "$1" 7) || return $?
  printf '%s %s %s\n' "$(pr_week_tag "$prev")" "$(pr_week_tag "$1")" "$(pr_week_tag "$next")"
}
