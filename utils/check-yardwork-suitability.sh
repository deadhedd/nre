#!/bin/sh
# Update the daily note with a yard work suitability check using Open-Meteo.

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
commit_helper="$script_dir/commit.sh"

vault_root="$HOME/automation/obsidian/vaults/Main"

# ---- Tunables ----
LAT=47.7423
LON=-121.9857
TEMP_CAP_F=70              # Max acceptable temp for "good" conditions
EARLY_HOUR_START=0         # Inclusive (local time)
EARLY_HOUR_END=6           # Inclusive (local time)

API_URL="https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&hourly=temperature_2m,dew_point_2m&temperature_unit=fahrenheit&timezone=America/Los_Angeles"

# Fetch forecast data
data=$(curl -fsS "$API_URL")

today=$(date +%Y-%m-%d)

# Flag if ANY early morning hour (00:00–06:59 by default) is "humid/unsuitable":
# temp < dew_point (i.e., likely muggy/condensation).
early_unsuitable=$(
  echo "$data" | jq --arg today "$today" \
    --argjson hs "$EARLY_HOUR_START" --argjson he "$EARLY_HOUR_END" '
      [ range(0; (.hourly.time|length)) as $i
        | .hourly.time[$i] as $ts
        | ($ts | startswith($today + "T")) as $is_today
        | ( $is_today
            and (( $ts[11:13] | tonumber ) >= $hs)
            and (( $ts[11:13] | tonumber ) <= $he)
            and (.hourly.temperature_2m[$i] < .hourly.dew_point_2m[$i])
          )
      ] | map(select(.)) | length > 0
    '
)

# Flag if ANY hour today reaches/exceeds the temperature cap.
high_temp_unsuitable=$(
  echo "$data" | jq --arg today "$today" --argjson cap "$TEMP_CAP_F" '
    [ range(0; (.hourly.time|length)) as $i
      | select(.hourly.time[$i] | startswith($today + "T"))
      | .hourly.temperature_2m[$i]
    ] | map(select(. >= $cap)) | length > 0
  '
)

if [ "$early_unsuitable" = "true" ] || [ "$high_temp_unsuitable" = "true" ]; then
  message="❌ Not ideal for yard work today."
else
  message="✅ Good yard work conditions expected today."
fi

note_path="$HOME/automation/obsidian/vaults/Main/Periodic Notes/Daily Notes/$today.md"

if [ -f "$note_path" ]; then
  tmp=$(mktemp)
  # Replace the marker once; keep the rest of the file intact.
  sed "s/<!-- yard-work-check -->/$message/" "$note_path" > "$tmp"
  mv "$tmp" "$note_path"
  echo "Yard work suitability check completed."

  if [ -x "$commit_helper" ]; then
    "$commit_helper" "$vault_root" "yard work suitability: $today" "$note_path"
  else
    printf '⚠️ commit helper not found: %s\n' "$commit_helper" >&2
  fi
else
  echo "Daily note not found: $note_path" >&2
  exit 1
fi
