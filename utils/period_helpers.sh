#!/bin/sh
# Utilities for working with years, months, quarters and weeks.

set -e

get_current_year() { date +%Y; }
get_prev_year() { echo $(( $(get_current_year) - 1 )); }
get_next_year() { echo $(( $(get_current_year) + 1 )); }

get_current_quarter() { echo $(( ( $(date +%m) + 2 ) / 3 )); }
get_quarter_tag() { printf 'Q%s-%s\n' "$(get_current_quarter)" "$(get_current_year)"; }

month_tag() {
  if [ "$1" ]; then
    date -d "$1" +%Y-%m
  else
    date +%Y-%m
  fi
}

get_current_month_tag() { month_tag; }
get_prev_month_tag() { date -d "$(date +%Y-%m-01) -1 month" +%Y-%m; }
get_next_month_tag() { date -d "$(date +%Y-%m-01) +1 month" +%Y-%m; }

week_tag() {
  if [ "$1" ]; then
    date -d "$1" +%G-W%V
  else
    date +%G-W%V
  fi
}

get_current_week_tag() { week_tag; }
get_prev_week_tag() { date -d 'last week' +%G-W%V; }
get_next_week_tag() { date -d 'next week' +%G-W%V; }

case "$1" in
  getCurrentYear) get_current_year;;
  getPrevYear) get_prev_year;;
  getNextYear) get_next_year;;
  getCurrentQuarter) get_current_quarter;;
  getQuarterTag) get_quarter_tag;;
  getCurrentMonthTag) get_current_month_tag;;
  getPrevMonthTag) get_prev_month_tag;;
  getNextMonthTag) get_next_month_tag;;
  getCurrentWeekTag) get_current_week_tag;;
  getPrevWeekTag) get_prev_week_tag;;
  getNextWeekTag) get_next_week_tag;;
  *) echo "Usage: $0 {getCurrentYear|getPrevYear|getNextYear|getCurrentQuarter|getQuarterTag|getCurrentMonthTag|getPrevMonthTag|getNextMonthTag|getCurrentWeekTag|getPrevWeekTag|getNextWeekTag}" >&2; exit 1;;
esac
