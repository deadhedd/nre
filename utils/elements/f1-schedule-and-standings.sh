#!/bin/sh
# Display upcoming F1 schedule and standings. POSIX/OpenBSD compatible.
# WARN/ERR lines surface semantic/operational failures for script-status-report.sh.

set -eu

log_info() { printf 'INFO %s\n' "$*"; }
log_warn() { printf 'WARN %s\n' "$*"; }
log_err() { printf 'ERR %s\n' "$*"; }

# ---------- Portable date helpers ----------
to_epoch() { date -u -j -f "%Y-%m-%d" "$1" "+%s"; }      # YYYY-MM-DD -> epoch
from_epoch() { date -u -r "$1" "+%Y-%m-%d"; }            # epoch -> YYYY-MM-DD
add_days() { sec=$(to_epoch "$1"); sec=$((sec + $2*86400)); from_epoch "$sec"; }
diff_days() { d1=$(to_epoch "$1"); d2=$(to_epoch "$2"); echo $(( (d1 - d2) / 86400 )); }

flag_for() {
  case "$1" in
    Australia) echo "🇦🇺";; China) echo "🇨🇳";; Japan) echo "🇯🇵";; Bahrain) echo "🇧🇭";;
    "Saudi Arabia") echo "🇸🇦";; USA|"United States") echo "🇺🇸";; Italy) echo "🇮🇹";;
    Monaco) echo "🇲🇨";; Spain) echo "🇪🇸";; Canada) echo "🇨🇦";; Austria) echo "🇦🇹";;
    UK|"United Kingdom") echo "🇬🇧";; Belgium) echo "🇧🇪";; Hungary) echo "🇭🇺";;
    Netherlands) echo "🇳🇱";; Azerbaijan) echo "🇦🇿";; Singapore) echo "🇸🇬";;
    Mexico) echo "🇲🇽";; Brazil) echo "🇧🇷";; Qatar) echo "🇶🇦";;
    UAE|"United Arab Emirates") echo "🇦🇪";; *) echo "🏳️";;
  esac
}

log_info "Starting Formula 1 schedule and standings fetch"
today=$(date +%Y-%m-%d)
log_info "Today's date: $today"
printf "# 🏎️ Formula 1\n\n"

# ---------- Fetch schedule ----------
if ! command -v jq >/dev/null 2>&1; then
  log_err "'jq' is required but not found."
  exit 1
fi

log_info "Fetching current season schedule from Ergast"
if ! schedule=$(curl -fsS https://api.jolpi.ca/ergast/f1/current.json 2>/dev/null); then
  log_err "Could not load race schedule."
  exit 1
fi
log_info "Schedule retrieved successfully"

log_info "Parsing schedule entries"

if ! race_lines=$(echo "$schedule" |
  jq -r '.MRData.RaceTable.Races[] | [.raceName, .date, .Circuit.Location.country] | @tsv'); then
  log_err "Failed to parse race schedule response."
  exit 1
fi

num_races=$(printf '%s\n' "$race_lines" | awk 'NF > 0' | wc -l | tr -d ' ')
log_info "Found $num_races races in schedule"

TAB=$(printf '\t')

events=""
next_race=""  # "name<TAB>date<TAB>country"

# Use a here-doc so variable assignments persist (no subshell)
while IFS="$TAB" read -r name date country; do
  practice=$(add_days "$date" -2)
  quali=$(add_days "$date" -1)

  if [ "$(diff_days "$today" "$practice")" -eq 0 ]; then
    events="$events- 🛠️ **Practice** — $name $(flag_for "$country")\n"
  elif [ "$(diff_days "$today" "$quali")" -eq 0 ]; then
    events="$events- ⏱️ **Qualifying / Sprint** — $name $(flag_for "$country")\n"
  elif [ "$(diff_days "$today" "$date")" -eq 0 ]; then
    events="$events- 🏁 **Race Day** — $name $(flag_for "$country")\n"
  elif [ -z "$next_race" ] && [ "$(diff_days "$date" "$today")" -gt 0 ]; then
    next_race="$name$TAB$date$TAB$country"
  fi
done <<EOF_SCHEDULE
$race_lines
EOF_SCHEDULE

if [ -n "$events" ]; then
  log_info "There are events happening this weekend"
  printf '### 📆 This Weekend:\n%s' "$events"
elif [ -n "$next_race" ]; then
  IFS="$TAB" read -r nname ndate ncountry <<EOF_NR
$next_race
EOF_NR
  practice=$(add_days "$ndate" -2)
  days_until=$(diff_days "$practice" "$today")
  plural=s; [ "$days_until" -eq 1 ] && plural=""
  log_info "Next race identified: $nname on $ndate"
  printf '**⏳ Next Grand Prix:**\n- %s %s — %s\n- ⌛ Practice starts in %d day%s (on %s)\n' \
    "$nname" "$(flag_for "$ncountry")" "$ndate" "$days_until" "$plural" "$practice"
else
  log_warn "No upcoming Formula 1 races found in schedule data."
  echo '🚫 No upcoming Formula 1 races found.'
fi
echo

# ---------- Standings ----------
log_info "Fetching driver standings"
if ! drivers=$(curl -fsS https://api.jolpi.ca/ergast/f1/current/driverStandings.json 2>/dev/null); then
  log_err "Could not load driver standings."
  exit 1
fi
log_info "Fetching constructor standings"
if ! constructors=$(curl -fsS https://api.jolpi.ca/ergast/f1/current/constructorStandings.json 2>/dev/null); then
  log_err "Could not load constructor standings."
  exit 1
fi

if [ -n "$drivers" ] && [ -n "$constructors" ]; then
  log_info "Standings data retrieved successfully"
  echo "### 📊 Driver Standings"
  echo "$drivers" |
    jq -r '.MRData.StandingsTable.StandingsLists[0].DriverStandings | .[0:5][] |
            [.position, .Driver.givenName, .Driver.familyName, .Constructors[0].name, .points] | @tsv' |
    while IFS="$TAB" read -r pos given family team points; do
      [ "$family" = "Norris" ] && name="**$given $family**" || name="$given $family"
      printf -- "- %s. %s (%s) – %s pts\n" "$pos" "$name" "$team" "$points"
    done
  echo

  echo "### 🏎️ Constructor Standings"
  echo "$constructors" |
    jq -r '.MRData.StandingsTable.StandingsLists[0].ConstructorStandings | .[0:5][] |
            [.position, .Constructor.name, .points] | @tsv' |
    while IFS="$TAB" read -r pos team points; do
      [ "$team" = "McLaren" ] && tname="**$team**" || tname="$team"
      printf -- "- %s. %s – %s pts\n" "$pos" "$tname" "$points"
    done
else
  log_warn "Standings data missing from Ergast response."
fi

log_info "Formula 1 data update complete"
