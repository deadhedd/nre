#!/bin/sh
# Display upcoming F1 schedule and standings.

set -e

diff_days() {
  d1=$(date -d "$1" +%s)
  d2=$(date -d "$2" +%s)
  echo $(( (d1 - d2) / 86400 ))
}

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

today=$(date +%Y-%m-%d)
echo "# 🏎️ Formula 1\n"

schedule=$(curl -fsS https://api.jolpi.ca/ergast/f1/current.json 2>/dev/null) || {
  echo "⚠️ Could not load race schedule."
  exit 0
}

race_lines=$(echo "$schedule" | jq -r '.MRData.RaceTable.Races[] | [.raceName, .date, .Circuit.Location.country] | @tsv')

TAB=$(printf '\t')

events=""
next_race=""
while IFS="$TAB" read -r name date country; do
  practice=$(date -d "$date -2 days" +%Y-%m-%d)
  quali=$(date -d "$date -1 day" +%Y-%m-%d)
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
  printf '### 📆 This Weekend:\n%s' "$events"
elif [ -n "$next_race" ]; then
  IFS="$TAB" read -r nname ndate ncountry <<EOF_NR
$next_race
EOF_NR
  practice=$(date -d "$ndate -2 days" +%Y-%m-%d)
  days_until=$(diff_days "$practice" "$today")
  plural=s
  [ "$days_until" -eq 1 ] && plural=""
  printf '**⏳ Next Grand Prix:**\n- %s %s — %s\n- ⌛ Practice starts in %d day%s (on %s)\n' \
    "$nname" "$(flag_for "$ncountry")" "$ndate" "$days_until" "$plural" "$practice"
else
  echo '🚫 No upcoming Formula 1 races found.'
fi

drivers=$(curl -fsS https://api.jolpi.ca/ergast/f1/current/driverStandings.json 2>/dev/null) || drivers=""
constructors=$(curl -fsS https://api.jolpi.ca/ergast/f1/current/constructorStandings.json 2>/dev/null) || constructors=""

if [ -n "$drivers" ] && [ -n "$constructors" ]; then
  echo "\n### 📊 Driver Standings"
  echo "$drivers" | jq -r '.MRData.StandingsTable.StandingsLists[0].DriverStandings[0:5] | [.position, .Driver.givenName, .Driver.familyName, .Constructors[0].name, .points] | @tsv' | \
    while IFS="$TAB" read -r pos given family team points; do
      if [ "$family" = "Norris" ]; then
        name="<div style=\"color: yellow; text-shadow: 0 0 5px gold; font-weight: bold;\">$given $family</div>"
      else
        name="$given $family"
      fi
      printf '- %s. %s (%s) – %s pts\n' "$pos" "$name" "$team" "$points"
    done

  echo "\n### 🏎️ Constructor Standings"
  echo "$constructors" | jq -r '.MRData.StandingsTable.StandingsLists[0].ConstructorStandings[0:5] | [.position, .Constructor.name, .points] | @tsv' | \
    while IFS="$TAB" read -r pos team points; do
      if [ "$team" = "McLaren" ]; then
        name="<div style=\"color: yellow; text-shadow: 0 0 5px gold; font-weight: bold;\">$team</div>"
      else
        name="$team"
      fi
      printf '- %s. %s – %s pts\n' "$pos" "$name" "$points"
    done
else
  echo "\n⚠️ Could not load standings."
fi
