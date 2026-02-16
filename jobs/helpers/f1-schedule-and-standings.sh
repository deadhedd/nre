#!/bin/sh
# f1-schedule-and-standings.sh
# Produce a small Markdown block: upcoming F1 context + top standings.
#
# Leaf script (wrapper required). POSIX/OpenBSD compatible.
# Stdout: markdown only. Stderr: diagnostics only (INFO/WARN/ERROR prefixes).
#
# Author: deadhedd
# License: MIT
# shellcheck shell=sh

set -eu

###############################################################################
# Logging (leaf responsibility: emit correctly-formatted messages to stderr)
###############################################################################

log_debug() { printf '%s\n' "DEBUG: $*" >&2; }
log_info()  { printf '%s\n' "INFO: $*"  >&2; }
log_warn()  { printf '%s\n' "WARN: $*"  >&2; }
log_error() { printf '%s\n' "ERROR: $*" >&2; }

###############################################################################
# Resolve paths + self-wrap
###############################################################################

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)

# C1 bootstrap rule: wrapper location assumed stable relative to this file
wrap="$script_dir/../engine/wrap.sh"
script_path="$script_dir/$(basename -- "$0")"

if [ "${JOB_WRAP_ACTIVE:-0}" != "1" ]; then
  # Fail-fast if wrapper is missing; don't silently run unwrapped.
  exec /bin/sh "$wrap" "$script_path" "$@"
fi

###############################################################################
# Environment
###############################################################################

# Cron-safe PATH (put /usr/local/bin first)
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

###############################################################################
# Portable date helpers (BSD/OpenBSD)
###############################################################################

to_epoch()   { date -u -j -f "%Y-%m-%d" "$1" "+%s"; }  # YYYY-MM-DD -> epoch
from_epoch() { date -u -r "$1" "+%Y-%m-%d"; }          # epoch -> YYYY-MM-DD

add_days() {
  d=$1
  n=$2
  sec=$(to_epoch "$d")
  sec=$((sec + n*86400))
  from_epoch "$sec"
}

# diff_days A B = (A - B) in days (integer)
diff_days() {
  d1=$(to_epoch "$1")
  d2=$(to_epoch "$2")
  echo $(( (d1 - d2) / 86400 ))
}

###############################################################################
# Small presentation helpers (Markdown output may include Unicode)
###############################################################################

flag_for() {
  case "$1" in
    Australia) echo "🇦🇺";;
    China) echo "🇨🇳";;
    Japan) echo "🇯🇵";;
    Bahrain) echo "🇧🇭";;
    "Saudi Arabia") echo "🇸🇦";;
    USA|"United States") echo "🇺🇸";;
    Italy) echo "🇮🇹";;
    Monaco) echo "🇲🇨";;
    Spain) echo "🇪🇸";;
    Canada) echo "🇨🇦";;
    Austria) echo "🇦🇹";;
    UK|"United Kingdom") echo "🇬🇧";;
    Belgium) echo "🇧🇪";;
    Hungary) echo "🇭🇺";;
    Netherlands) echo "🇳🇱";;
    Azerbaijan) echo "🇦🇿";;
    Singapore) echo "🇸🇬";;
    Mexico) echo "🇲🇽";;
    Brazil) echo "🇧🇷";;
    Qatar) echo "🇶🇦";;
    UAE|"United Arab Emirates") echo "🇦🇪";;
    *) echo "🏳️";;
  esac
}

###############################################################################
# Main
###############################################################################

log_info "cadence=daily"
log_info "Starting F1 schedule/standings fetch"

# Fail early with NO stdout if prereqs are missing.
if ! command -v jq >/dev/null 2>&1; then
  log_error "jq is required but not found"
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  log_error "curl is required but not found"
  exit 1
fi

today=$(date +%Y-%m-%d)
log_info "Today is $today"

# --- Fetch schedule ---
log_info "Fetching current season schedule (Ergast via jolpi)"
if ! schedule_json=$(curl -fsS https://api.jolpi.ca/ergast/f1/current.json 2>/dev/null); then
  log_error "Could not load race schedule"
  exit 1
fi

if ! race_lines=$(printf '%s' "$schedule_json" |
  jq -r '.MRData.RaceTable.Races[] | [.raceName, .date, .Circuit.Location.country] | @tsv'); then
  log_error "Failed to parse race schedule response"
  exit 1
fi

num_races=$(printf '%s\n' "$race_lines" | awk 'NF > 0' | wc -l | tr -d ' ')
log_info "Parsed schedule: races=$num_races"

TAB=$(printf '\t')
events=""
next_race=""  # "name<TAB>date<TAB>country"

# Use a here-doc so variable assignments persist (no subshell)
while IFS="$TAB" read -r name date country; do
  [ -n "$name" ] || continue
  [ -n "$date" ] || continue

  practice=$(add_days "$date" -2)
  quali=$(add_days "$date" -1)

  if [ "$(diff_days "$today" "$practice")" -eq 0 ]; then
    events="${events}- 🛠️ **Practice** — ${name} $(flag_for "$country")\n"
  elif [ "$(diff_days "$today" "$quali")" -eq 0 ]; then
    events="${events}- ⏱️ **Qualifying / Sprint** — ${name} $(flag_for "$country")\n"
  elif [ "$(diff_days "$today" "$date")" -eq 0 ]; then
    events="${events}- 🏁 **Race Day** — ${name} $(flag_for "$country")\n"
  elif [ -z "$next_race" ] && [ "$(diff_days "$date" "$today")" -gt 0 ]; then
    next_race="${name}${TAB}${date}${TAB}${country}"
  fi
done <<EOF_SCHEDULE
$race_lines
EOF_SCHEDULE

# --- Fetch standings ---
log_info "Fetching driver standings"
if ! drivers_json=$(curl -fsS https://api.jolpi.ca/ergast/f1/current/driverStandings.json 2>/dev/null); then
  log_error "Could not load driver standings"
  exit 1
fi

log_info "Fetching constructor standings"
if ! constructors_json=$(curl -fsS https://api.jolpi.ca/ergast/f1/current/constructorStandings.json 2>/dev/null); then
  log_error "Could not load constructor standings"
  exit 1
fi

# Parse standings now (still no stdout yet)
if ! drivers_top5=$(printf '%s' "$drivers_json" |
  jq -r '.MRData.StandingsTable.StandingsLists[0].DriverStandings | .[0:5][] |
         [.position, .Driver.givenName, .Driver.familyName, .Constructors[0].name, .points] | @tsv'); then
  log_error "Failed to parse driver standings response"
  exit 1
fi

if ! constructors_top5=$(printf '%s' "$constructors_json" |
  jq -r '.MRData.StandingsTable.StandingsLists[0].ConstructorStandings | .[0:5][] |
         [.position, .Constructor.name, .points] | @tsv'); then
  log_error "Failed to parse constructor standings response"
  exit 1
fi

###############################################################################
# Build Markdown (stdout payload) — ONLY after all required work succeeded
###############################################################################

md="# 🏎️ Formula 1\n\n"

if [ -n "$events" ]; then
  log_info "Weekend events detected"
  md="${md}### 📆 This Weekend:\n$(printf '%b' "$events")\n"
elif [ -n "$next_race" ]; then
  IFS="$TAB" read -r nname ndate ncountry <<EOF_NR
$next_race
EOF_NR
  practice=$(add_days "$ndate" -2)
  days_until=$(diff_days "$practice" "$today")
  plural="s"
  [ "$days_until" -eq 1 ] && plural=""
  log_info "Next race is $nname on $ndate"
  md="${md}**⏳ Next Grand Prix:**\n- ${nname} $(flag_for "$ncountry") — ${ndate}\n- ⌛ Practice starts in ${days_until} day${plural} (on ${practice})\n\n"
else
  log_warn "No upcoming races found in schedule data"
  md="${md}🚫 No upcoming Formula 1 races found.\n\n"
fi

md="${md}### 📊 Driver Standings\n"
# Keep your bolding preferences: Norris + McLaren
while IFS="$TAB" read -r pos given family team points; do
  [ -n "$pos" ] || continue
  name="${given} ${family}"
  [ "$family" = "Norris" ] && name="**${name}**"
  md="${md}- ${pos}. ${name} (${team}) – ${points} pts\n"
done <<EOF_DTOP
$drivers_top5
EOF_DTOP
md="${md}\n"

md="${md}### 🏎️ Constructor Standings\n"
while IFS="$TAB" read -r pos team points; do
  [ -n "$pos" ] || continue
  tname="$team"
  [ "$team" = "McLaren" ] && tname="**${team}**"
  md="${md}- ${pos}. ${tname} – ${points} pts\n"
done <<EOF_CTOP
$constructors_top5
EOF_CTOP
md="${md}\n"

log_info "F1 schedule/standings complete"

# Stdout: markdown only
printf '%b' "$md"
