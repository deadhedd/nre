#!/bin/sh
# Update the daily note with a yard work suitability check using Open-Meteo.

set -e

LAT=47.7423
LON=-121.9857
API_URL="https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&hourly=temperature_2m,dew_point_2m&temperature_unit=fahrenheit&timezone=America/Los_Angeles"

data=$(curl -fsS "$API_URL")

suitable=$(echo "$data" | jq '[range(0; (.hourly.time|length)) as $i | (.hourly.time[$i] | capture("T(?<h>[0-9]{2}):").h|tonumber) as $hour | select($hour>=0 and $hour<=6) | .hourly.temperature_2m[$i] as $temp | .hourly.dew_point_2m[$i] as $dew | select($temp < 70 and $dew < $temp)] | length > 0')

if [ "$suitable" = "true" ]; then
  message="✅ Good yard work conditions expected this morning."
else
  message="❌ Not ideal for yard work this morning."
fi

today=$(date +%Y-%m-%d)
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
