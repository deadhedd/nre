#!/bin/sh
# Update the daily note with a yard work suitability check using Open-Meteo.

set -eu

log_info() { printf 'INFO %s\n' "$*"; }
log_warn() { printf 'WARN %s\n' "$*"; }
log_err()  { printf 'ERR %s\n'  "$*"; }

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
core_dir=$(dirname -- "$script_dir")/core
job_wrap="$core_dir/job-wrap.sh"
script_path="$script_dir/$(basename "$0")"

if [ "${JOB_WRAP_ACTIVE:-0}" != "1" ] && [ -x "$job_wrap" ]; then
  JOB_WRAP_ACTIVE=1 exec /bin/sh "$job_wrap" "$script_path" "$@"
fi

vault_path="${VAULT_PATH:-/home/obsidian/vaults/Main}"
vault_root="${vault_path%/}"
periodic_dir="${vault_root}/Periodic Notes"
daily_note_dir="${periodic_dir%/}/Daily Notes"

# ---- Tunables ----
LAT=47.7423
LON=-121.9857
TEMP_CAP_F=70              # Max acceptable temp for "good" conditions
EARLY_HOUR_START=0         # Inclusive (local time)
EARLY_HOUR_END=6           # Inclusive (local time)

API_URL="https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&hourly=temperature_2m,dew_point_2m&temperature_unit=fahrenheit&timezone=America/Los_Angeles"

# Fetch forecast data
if ! data=$(curl -fsS "$API_URL"); then
  log_err "Failed to fetch forecast data from API"
  exit 1
fi

today=$(date +%Y-%m-%d)

# Flag if ANY early morning hour (00:00–06:59 by default) is "humid/unsuitable":
# temp < dew_point (i.e., likely muggy/condensation).
if ! early_unsuitable=$(
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
); then
  log_err "Failed to parse forecast data for early hours"
  exit 1
fi

# Flag if ANY hour today reaches/exceeds the temperature cap.
if ! high_temp_unsuitable=$(
  echo "$data" | jq --arg today "$today" --argjson cap "$TEMP_CAP_F" '
    [ range(0; (.hourly.time|length)) as $i
      | select(.hourly.time[$i] | startswith($today + "T"))
      | .hourly.temperature_2m[$i]
    ] | map(select(. >= $cap)) | length > 0
  '
); then
  log_err "Failed to parse forecast data for temperature cap"
  exit 1
fi

if [ "$early_unsuitable" = "true" ] || [ "$high_temp_unsuitable" = "true" ]; then
  message="❌ Not ideal for yard work today."
else
  message="✅ Good yard work conditions expected today."
fi

note_path="${daily_note_dir%/}/${today}.md"

if [ -f "$note_path" ]; then
  tmp=$(mktemp)
  # Replace the marker once; keep the rest of the file intact.
  sed "s/<!-- yard-work-check -->/$message/" "$note_path" > "$tmp"

  if cmp -s "$note_path" "$tmp"; then
    rm -f "$tmp"
    log_err "Marker <!-- yard-work-check --> not found in note; no update applied"
    exit 1
  fi

  # Replace the original note with the temp file.
  # We silence the harmless "set owner/group: Operation not permitted" noise
  # that happens when mv crosses filesystems, but still let real errors kill
  # the script via `set -e`.
  mv "$tmp" "$note_path" 2>/dev/null

  # Ensure the resulting file is readable by the git user (and others),
  # so `git add` in commit_helper doesn't hit "Permission denied".
  # First try group-writable (664), fall back to 644 if needed.
  chmod 664 "$note_path" 2>/dev/null || chmod 644 "$note_path" 2>/dev/null || true

  log_info "Yard work suitability check completed"
else
  log_err "Daily note not found: $note_path"
  exit 1
fi
