#!/bin/sh
# Update the daily note with a yard work suitability check using Open-Meteo.

set -e

LAT=47.7423
LON=-121.9857
API_URL="https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&hourly=temperature_2m,dew_point_2m&temperature_unit=fahrenheit&timezone=America/Los_Angeles"

data=$(curl -fsS "$API_URL")

today=$(date +%Y-%m-%d)

early_unsuitable=$(echo "$data" | jq --arg today "$today" '[range(0; (.hourly.time|length)) as $i | (.hourly.time[$i] | capture("(?<date>\d{4}-\d{2}-\d{2})T(?<h>\d{2}):")) as $t | select($t.date == $today and ($t.h|tonumber) >= 0 and ($t.h|tonumber) <= 6 and .hourly.temperature_2m[$i] < .hourly.dew_point_2m[$i])] | length > 0')

high_temp_unsuitable=$(echo "$data" | jq --arg today "$today" '[range(0; (.hourly.time|length)) as $i | select(.hourly.time[$i] | startswith($today)) | .hourly.temperature_2m[$i]] | max >= 70')

if [ "$early_unsuitable" = "true" ] || [ "$high_temp_unsuitable" = "true" ]; then
  message="❌ Not ideal for yard work today."
else
  message="✅ Good yard work conditions expected today."
fi

note_path="$HOME/automation/obsidian/vaults/Main/000 - General Knowledge, Information Science, and Computing/005 - Computer Programming, Information, and Security/005.7 - Data/Daily Notes/$today.md"

if [ -f "$note_path" ]; then
  tmp=$(mktemp)
  sed "s/<!-- yard-work-check -->/$message/" "$note_path" > "$tmp"
  mv "$tmp" "$note_path"
  echo "Yard work suitability check completed."
else
  echo "Daily note not found: $note_path" >&2
  exit 1
fi
