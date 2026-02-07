#!/bin/sh
# Utilities for working with years, months, quarters and weeks.

set -eu


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

coerce_month_to_decimal() {
  month=${1:-}

  if [ -z "$month" ]; then
    printf '%s\n' 0
    return
  fi

  month=$(expr "$month" + 0)
  printf '%s\n' "$month"
}

get_current_year() { date +%Y; }
get_prev_year() { echo $(( $(get_current_year) - 1 )); }
get_next_year() { echo $(( $(get_current_year) + 1 )); }

get_current_quarter() {
  month=$(date +%m)
  month=$(coerce_month_to_decimal "$month")
  echo $(( (month + 2) / 3 ))
}
get_quarter_tag() { printf 'Q%s-%s\n' "$(get_current_quarter)" "$(get_current_year)"; }
get_quarter_tag_iso() { printf '%s-Q%s\n' "$(get_current_year)" "$(get_current_quarter)"; }

get_today() { date +%Y-%m-%d; }

get_local_iso_timestamp() { date '+%Y-%m-%dT%H:%M:%S%z'; }
get_utc_run_id() { date -u +%Y%m%dT%H%M%SZ; }
get_utc_epoch_seconds() { date -u +%s; }

get_current_date_parts() {
  today=$(get_today)
  year=$(printf '%s' "$today" | cut -d- -f1)
  month=$(printf '%s' "$today" | cut -d- -f2)
  day=$(printf '%s' "$today" | cut -d- -f3)
  printf '%s %s %s\n' "$year" "$month" "$day"
}

parse_utc_date() {
  if [ -z "${1:-}" ]; then
    printf 'ERR  %s\n' "parse_utc_date: missing date" >&2
    return 1
  fi
  input=$1
  year=${input%%-*}
  rest=${input#*-}
  if [ "$rest" = "$input" ]; then
    printf 'ERR  %s\n' "parse_utc_date: invalid format '$input'" >&2
    return 1
  fi
  month=${rest%%-*}
  day=${rest#*-}
  if [ "$day" = "$rest" ]; then
    printf 'ERR  %s\n' "parse_utc_date: invalid format '$input'" >&2
    return 1
  fi
  printf '%s %s %s\n' "$year" "$month" "$day"
}

parse_utc_time() {
  if [ -z "${1:-}" ]; then
    printf 'ERR  %s\n' "parse_utc_time: missing time" >&2
    return 1
  fi

  if ! parsed=$(awk -v time="$1" 'BEGIN {
    if (time !~ /^[0-9][0-9]:[0-9][0-9]$/) {
      exit 1
    }
    split(time, parts, ":")
    h = parts[1] + 0
    m = parts[2] + 0
    if (h < 0 || h > 23) {
      exit 1
    }
    if (m < 0 || m > 59) {
      exit 1
    }
    printf "%d %d\n", h, m
  }'); then
    printf 'ERR  %s\n' "parse_utc_time: invalid format '$1'" >&2
    return 1
  fi

  printf '%s\n' "$parsed"
}

month_tag() {
  if [ "${1:-}" ]; then
    case "$1" in
      ????-??)
        printf '%s\n' "$1"
        ;;
      ????-??-??)
        if parts=$(parse_utc_date "$1"); then
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
    date +%Y-%m
  fi
}

get_current_month_tag() { month_tag; }

add_months() {
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

get_prev_month_tag() {
  set -- $(add_months "$(date +%Y)" "$(date +%m)" -1)
  printf '%04d-%02d\n' "$1" "$2"
}

get_next_month_tag() {
  set -- $(add_months "$(date +%Y)" "$(date +%m)" 1)
  printf '%04d-%02d\n' "$1" "$2"
}

run_awk() {
  script=$1
  shift
  printf '%s\n%s\n' "$awk_common" "$script" | awk "$@" -f -
}

weekday_name_for_index() {
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

weekday_for_utc_date() {
  if ! parts=$(parse_utc_date "$1"); then
    return 1
  fi
  set -- $parts
  run_awk 'BEGIN {
    y = year + 0
    m = month + 0
    d = day + 0
    if (!verify_ymd(y, m, d, tmp)) exit 1
    idx = weekday_from_days(days_from_civil(y, m, d))
    printf "%d\n", idx
  }' -v year="$1" -v month="$2" -v day="$3"
}

week_tag() {
  if [ "${1:-}" ]; then
    if ! parts=$(parse_utc_date "$1"); then
      return 1
    fi
    set -- $parts
    run_awk 'BEGIN {
      y = year + 0
      m = month + 0
      d = day + 0
      if (!verify_ymd(y, m, d, tmp)) exit 1
      z = days_from_civil(y, m, d)
      iso_week_from_days(z, out, tmp2)
      printf "%04d-W%02d\n", out["year"], out["week"]
    }' -v year="$1" -v month="$2" -v day="$3"
  else
    today=$(get_today)
    week_tag "$today"
  fi
}

get_current_week_tag() { week_tag; }

get_prev_week_tag() {
  today=$(get_today)
  prev=$(shift_utc_date_by_days "$today" -7)
  week_tag "$prev"
}

get_next_week_tag() {
  today=$(get_today)
  next=$(shift_utc_date_by_days "$today" 7)
  week_tag "$next"
}

get_yesterday() {
  shift_utc_date_by_days "$(get_today)" -1
}

get_tomorrow() {
  shift_utc_date_by_days "$(get_today)" 1
}

get_today_utc() { date -u +%Y-%m-%d; }

is_utc_date_format() {
  if [ -z "${1:-}" ]; then
    return 1
  fi

  case "$1" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_valid_utc_date() {
  if ! is_utc_date_format "${1:-}"; then
    return 1
  fi

  if epoch_for_utc_date "$1" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

epoch_for_utc_date() {
  if [ -z "${1:-}" ]; then
    printf 'ERR  %s\n' "epoch_for_utc_date: missing date" >&2
    return 1
  fi

  if ! parts=$(parse_utc_date "$1"); then
    printf 'ERR  %s\n' "epoch_for_utc_date: invalid date format" >&2
    return 1
  fi

  set -- $parts
  run_awk 'BEGIN {
    y = year + 0
    m = month + 0
    d = day + 0
    if (!verify_ymd(y, m, d, tmp)) exit 1
    days = days_from_civil(y, m, d)
    printf "%.0f\n", days * 86400
  }' -v year="$1" -v month="$2" -v day="$3" || {
    printf 'ERR  %s\n' "epoch_for_utc_date: invalid date" >&2
    return 1
  }
}

epoch_for_utc_datetime() {
  if [ -z "${1:-}" ]; then
    printf 'ERR  %s\n' "epoch_for_utc_datetime: missing datetime" >&2
    return 1
  fi

  input=$1
  date_part=${input% *}
  time_part=${input#* }
  if [ "$date_part" = "$input" ] || [ -z "$time_part" ]; then
    printf 'ERR  %s\n' "epoch_for_utc_datetime: invalid datetime format" >&2
    return 1
  fi

  if ! date_fields=$(parse_utc_date "$date_part"); then
    printf 'ERR  %s\n' "epoch_for_utc_datetime: invalid date" >&2
    return 1
  fi

  if ! time_fields=$(parse_utc_time "$time_part"); then
    printf 'ERR  %s\n' "epoch_for_utc_datetime: invalid time" >&2
    return 1
  fi

  set -- $date_fields
  year=$1
  month=$2
  day=$3

  set -- $time_fields
  hour=$1
  minute=$2

  date_epoch=$(epoch_for_utc_date "$(printf '%04d-%02d-%02d' "$year" "$month" "$day")") || return 1
  printf '%s\n' $(( date_epoch + hour * 3600 + minute * 60 ))
}

utc_date_for_epoch() {
  if [ -z "${1:-}" ]; then
    printf 'ERR  %s\n' "utc_date_for_epoch: missing epoch" >&2
    return 1
  fi

  run_awk 'BEGIN {
    e = epoch + 0
    days = floor(e / 86400)
    civil_from_days(days, tmp)
    printf "%04d-%02d-%02d\n", tmp["y"], tmp["m"], tmp["d"]
  }' -v epoch="$1"
}

shift_epoch_by_days() {
  if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
    printf 'ERR  %s\n' "shift_epoch_by_days: requires epoch and day offset" >&2
    return 1
  fi

  run_awk 'BEGIN {
    e = epoch + 0
    d = days + 0
    printf "%.0f\n", e + d * 86400
  }' -v epoch="$1" -v days="$2"
}

shift_utc_date_by_days() {
  if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
    printf 'ERR  %s\n' "shift_utc_date_by_days: requires date and day offset" >&2
    return 1
  fi

  epoch=$(epoch_for_utc_date "$1") || return 1
  shifted=$(shift_epoch_by_days "$epoch" "$2") || return 1
  utc_date_for_epoch "$shifted"
}

format_epoch_local() {
  if [ -z "${1:-}" ]; then
    printf 'ERR  %s\n' "format_epoch_local: missing epoch" >&2
    return 1
  fi

  epoch=$1
  if [ "${2:-}" ]; then
    fmt=$2
  else
    fmt='%b %e, %Y %I:%M %p %Z'
  fi

  awk -v epoch="$epoch" -v fmt="$fmt" 'BEGIN { printf "%s\n", strftime(fmt, epoch) }'
}

epoch_for_local_datetime() {
  if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
    printf 'ERR  %s\n' "epoch_for_local_datetime: requires date and time" >&2
    return 1
  fi

  date_part=$1
  time_part=$2

  if ! date_fields=$(parse_utc_date "$date_part"); then
    printf 'ERR  %s\n' "epoch_for_local_datetime: invalid date" >&2
    return 1
  fi

  if ! time_fields=$(parse_utc_time "$time_part"); then
    printf 'ERR  %s\n' "epoch_for_local_datetime: invalid time" >&2
    return 1
  fi

  set -- $date_fields
  target_year=$1
  target_month=$2
  target_day=$3
  target_date=$(awk -v y="$target_year" -v m="$target_month" -v d="$target_day" 'BEGIN { printf "%04d-%02d-%02d\n", y+0, m+0, d+0 }') || return 1

  set -- $time_fields
  target_hour=$1
  target_minute=$2
  target_seconds=$(awk -v h="$target_hour" -v m="$target_minute" 'BEGIN { printf "%d\n", (h+0)*3600 + (m+0)*60 }') || return 1

  base_epoch=$(epoch_for_utc_date "$target_date") || return 1
  guess=$(( base_epoch + target_seconds ))

  iterations=0
  while [ "$iterations" -lt 8 ]; do
    info=$(format_epoch_local "$guess" "%Y-%m-%d %H:%M") || return 1
    local_date=${info%% *}
    local_time=${info#* }
    local_hour=${local_time%%:*}
    local_minute=${local_time#*:}

    if [ "$local_date" != "$target_date" ]; then
      local_day_epoch=$(epoch_for_utc_date "$local_date") || return 1
      if [ "$local_day_epoch" -gt "$base_epoch" ]; then
        guess=$(( guess - 86400 ))
        iterations=$(( iterations + 1 ))
        continue
      fi

      if [ "$local_day_epoch" -lt "$base_epoch" ]; then
        guess=$(( guess + 86400 ))
        iterations=$(( iterations + 1 ))
        continue
      fi

      printf 'ERR  %s\n' "epoch_for_local_datetime: failed to compare localized date" >&2
      return 1
    fi

    local_seconds=$(awk -v h="$local_hour" -v m="$local_minute" 'BEGIN { printf "%d\n", (h+0)*3600 + (m+0)*60 }') || return 1

    delta=$(( target_seconds - local_seconds ))
    if [ "$delta" -eq 0 ]; then
      printf '%s\n' "$guess"
      return 0
    fi

    guess=$(( guess + delta ))
    iterations=$(( iterations + 1 ))
  done

  printf 'ERR  %s\n' "epoch_for_local_datetime: failed to converge" >&2
  return 1
}

week_tag_for_epoch() {
  if [ -z "${1:-}" ]; then
    printf 'ERR  %s\n' "week_tag_for_epoch: missing epoch" >&2
    return 1
  fi

  run_awk 'BEGIN {
    e = epoch + 0
    days = floor(e / 86400)
    iso_week_from_days(days, out, tmp)
    printf "%04d-W%02d\n", out["year"], out["week"]
  }' -v epoch="$1"
}

week_tag_for_utc_date() {
  epoch=$(epoch_for_utc_date "$1") || return 1
  week_tag_for_epoch "$epoch"
}

week_nav_tags_for_utc_date() {
  if [ -z "${1:-}" ]; then
    printf 'ERR  %s\n' "week_nav_tags_for_utc_date: missing date" >&2
    return 1
  fi

  epoch=$(epoch_for_utc_date "$1") || return 1
  prev_epoch=$(shift_epoch_by_days "$epoch" -7) || return 1
  next_epoch=$(shift_epoch_by_days "$epoch" 7) || return 1

  printf '%s %s %s\n' \
    "$(week_tag_for_epoch "$prev_epoch")" \
    "$(week_tag_for_epoch "$epoch")" \
    "$(week_tag_for_epoch "$next_epoch")"
}

month_tag_for_epoch() {
  if [ -z "${1:-}" ]; then
    printf 'ERR  %s\n' "month_tag_for_epoch: missing epoch" >&2
    return 1
  fi

  run_awk 'BEGIN {
    e = epoch + 0
    days = floor(e / 86400)
    civil_from_days(days, tmp)
    printf "%04d-%02d\n", tmp["y"], tmp["m"]
  }' -v epoch="$1"
}

month_tag_for_utc_date() {
  epoch=$(epoch_for_utc_date "$1") || return 1
  month_tag_for_epoch "$epoch"
}

year_for_epoch() {
  if [ -z "${1:-}" ]; then
    printf 'ERR  %s\n' "year_for_epoch: missing epoch" >&2
    return 1
  fi

  run_awk 'BEGIN {
    e = epoch + 0
    days = floor(e / 86400)
    civil_from_days(days, tmp)
    printf "%04d\n", tmp["y"]
  }' -v epoch="$1"
}

year_for_utc_date() {
  epoch=$(epoch_for_utc_date "$1") || return 1
  year_for_epoch "$epoch"
}

quarter_tag_for_epoch() {
  if [ -z "${1:-}" ]; then
    printf 'ERR  %s\n' "quarter_tag_for_epoch: missing epoch" >&2
    return 1
  fi

  run_awk 'BEGIN {
    e = epoch + 0
    days = floor(e / 86400)
    civil_from_days(days, tmp)
    month = tmp["m"] + 0
    quarter = int((month + 2) / 3)
    printf "Q%d-%04d\n", quarter, tmp["y"]
  }' -v epoch="$1"
}

quarter_tag_for_utc_date() {
  epoch=$(epoch_for_utc_date "$1") || return 1
  quarter_tag_for_epoch "$epoch"
}

if [ "${0##*/}" = "date-period-helpers.sh" ] && [ $# -gt 0 ]; then
  case "$1" in
    getCurrentYear) get_current_year;;
    getPrevYear) get_prev_year;;
    getNextYear) get_next_year;;
    getCurrentQuarter) get_current_quarter;;
    getQuarterTag) get_quarter_tag;;
    getQuarterTagISO) get_quarter_tag_iso;;
    getToday) get_today;;
    getCurrentDateParts) get_current_date_parts;;
    getCurrentMonthTag) get_current_month_tag;;
    getPrevMonthTag) get_prev_month_tag;;
    getNextMonthTag) get_next_month_tag;;
    getCurrentWeekTag) get_current_week_tag;;
    getPrevWeekTag) get_prev_week_tag;;
    getNextWeekTag) get_next_week_tag;;
    getYesterday) get_yesterday;;
    getTomorrow) get_tomorrow;;
    *)
      printf 'ERR  %s\n' "Usage: $0 {getCurrentYear|getPrevYear|getNextYear|getCurrentQuarter|getQuarterTag|getQuarterTagISO|getToday|getCurrentDateParts|getCurrentMonthTag|getPrevMonthTag|getNextMonthTag|getCurrentWeekTag|getPrevWeekTag|getNextWeekTag|getYesterday|getTomorrow}" >&2
      exit 1
      ;;
  esac
fi
