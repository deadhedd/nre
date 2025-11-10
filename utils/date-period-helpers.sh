#!/bin/sh
# Utilities for working with years, months, quarters and weeks.

set -e

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

get_current_date_parts() {
  today=$(get_today)
  year=$(printf '%s' "$today" | cut -d- -f1)
  month=$(printf '%s' "$today" | cut -d- -f2)
  day=$(printf '%s' "$today" | cut -d- -f3)
  printf '%s %s %s\n' "$year" "$month" "$day"
}

month_tag() {
  if [ "${1:-}" ]; then
    date -d "$1" +%Y-%m
  else
    date +%Y-%m
  fi
}

get_current_month_tag() { month_tag; }
get_prev_month_tag() { date -d "$(date +%Y-%m-01) -1 month" +%Y-%m; }
get_next_month_tag() { date -d "$(date +%Y-%m-01) +1 month" +%Y-%m; }

week_tag() {
  if [ "${1:-}" ]; then
    date -d "$1" +%G-W%V
  else
    date +%G-W%V
  fi
}

get_current_week_tag() { week_tag; }
get_prev_week_tag() { date -d 'last week' +%G-W%V; }
get_next_week_tag() { date -d 'next week' +%G-W%V; }

get_yesterday() { TZ=UTC+24 date +%Y-%m-%d; }
get_tomorrow() { TZ=UTC-24 date +%Y-%m-%d; }

get_today_utc() { date -u +%Y-%m-%d; }

epoch_for_utc_date() {
  if [ -z "${1:-}" ]; then
    printf '%s\n' "epoch_for_utc_date: missing date" >&2
    return 1
  fi

  date -u -d "$1" +%s
}

shift_epoch_by_days() {
  if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
    printf '%s\n' "shift_epoch_by_days: requires epoch and day offset" >&2
    return 1
  fi

  epoch=$1
  days=$2
  printf '%s\n' "$(( epoch + days * 86400 ))"
}

week_tag_for_epoch() {
  if [ -z "${1:-}" ]; then
    printf '%s\n' "week_tag_for_epoch: missing epoch" >&2
    return 1
  fi

  date -u -d "@$1" +%G-W%V
}

week_tag_for_utc_date() {
  epoch=$(epoch_for_utc_date "$1") || return 1
  week_tag_for_epoch "$epoch"
}

month_tag_for_epoch() {
  if [ -z "${1:-}" ]; then
    printf '%s\n' "month_tag_for_epoch: missing epoch" >&2
    return 1
  fi

  date -u -d "@$1" +%Y-%m
}

month_tag_for_utc_date() {
  epoch=$(epoch_for_utc_date "$1") || return 1
  month_tag_for_epoch "$epoch"
}

year_for_epoch() {
  if [ -z "${1:-}" ]; then
    printf '%s\n' "year_for_epoch: missing epoch" >&2
    return 1
  fi

  date -u -d "@$1" +%Y
}

year_for_utc_date() {
  epoch=$(epoch_for_utc_date "$1") || return 1
  year_for_epoch "$epoch"
}

quarter_tag_for_epoch() {
  if [ -z "${1:-}" ]; then
    printf '%s\n' "quarter_tag_for_epoch: missing epoch" >&2
    return 1
  fi

  month=$(date -u -d "@$1" +%m)
  month=$(coerce_month_to_decimal "$month")
  year=$(year_for_epoch "$1")
  quarter=$(( (month + 2) / 3 ))
  printf 'Q%d-%s\n' "$quarter" "$year"
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
      echo "Usage: $0 {getCurrentYear|getPrevYear|getNextYear|getCurrentQuarter|getQuarterTag|getQuarterTagISO|getToday|getCurrentDateParts|getCurrentMonthTag|getPrevMonthTag|getNextMonthTag|getCurrentWeekTag|getPrevWeekTag|getNextWeekTag|getYesterday|getTomorrow}" >&2
      exit 1
      ;;
  esac
fi
