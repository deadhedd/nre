#!/bin/sh
# jobs/check-yardwork-suitability.sh
# Update today's daily note with a yard work suitability check (Open-Meteo).
#
# Leaf job (wrapper required).
#
# Cadence: daily
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
script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
wrap="$script_dir/../engine/wrap.sh"

case "$0" in
  /*) script_path=$0 ;;
  *)  script_path="$script_dir/$0" ;;
esac

if [ "${JOB_WRAP_ACTIVE:-0}" != "1" ]; then
  exec /bin/sh "$wrap" "$script_path" "$@"
fi

###############################################################################
# Environment normalization (cron-safe)
###############################################################################
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

###############################################################################
# Cadence declaration (for reporter freshness)
###############################################################################
log_info "cadence=daily"

###############################################################################
# Vault paths
###############################################################################
vault_root="${VAULT_ROOT:-${VAULT_PATH:-/home/obsidian/vaults/Main}}"
vault_root=${vault_root%/}

daily_note_dir="${vault_root}/Periodic Notes/Daily Notes"

###############################################################################
# Tunables
###############################################################################
LAT=47.7423
LON=-121.9857
TEMP_CAP_F=70           # "Too hot" at or above this temp
WORK_START_HOUR=8       # 08:00 local
PRE_START_HOUR=7        # 07:00 local
DEW_SPREAD_F=2          # Dew likely if (temp - dew point) <= this at 07:00 or 08:00

API_URL="https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&hourly=temperature_2m,dew_point_2m,precipitation_probability&temperature_unit=fahrenheit&timezone=America/Los_Angeles"

###############################################################################
# Fetch forecast data
###############################################################################
log_info "Fetching forecast from Open-Meteo"
if ! data=$(curl -fsS "$API_URL"); then
  log_error "Failed to fetch forecast data from API"
  exit 1
fi

today=$(date +%Y-%m-%d)

###############################################################################
# Log raw decision inputs (for dew/rain/heat tuning visibility)
###############################################################################
log_info "Decision inputs for $today (hours $PRE_START_HOUR and $WORK_START_HOUR):"

printf '%s' "$data" | jq -r \
  --arg today "$today" \
  --argjson h1 "$PRE_START_HOUR" \
  --argjson h2 "$WORK_START_HOUR" '
    range(0; (.hourly.time|length)) as $i
    | .hourly.time[$i] as $ts
    | select($ts | startswith($today + "T"))
    | ($ts[11:13] | tonumber) as $h
    | select($h == $h1 or $h == $h2)
    | .hourly.temperature_2m[$i] as $t
    | .hourly.dew_point_2m[$i] as $d
    | .hourly.precipitation_probability[$i] as $p
    | "Hour \($h): temp=\($t)F dew=\($d)F spread=\($t - $d)F precip=\($p)%"
  ' 2>/dev/null | while IFS= read -r line; do
    log_info "$line"
  done

###############################################################################
# Evaluate suitability
###############################################################################
# dew_likely: (temp - dew_point) <= threshold at 07:00 or 08:00
if ! dew_likely=$(
  printf '%s' "$data" | jq --arg today "$today" \
    --argjson h1 "$PRE_START_HOUR" --argjson h2 "$WORK_START_HOUR" \
    --argjson thr "$DEW_SPREAD_F" '
      [ range(0; (.hourly.time|length)) as $i
        | .hourly.time[$i] as $ts
        | select($ts | startswith($today + "T"))
        | ($ts[11:13] | tonumber) as $h
        | select($h == $h1 or $h == $h2)
        | (.hourly.temperature_2m[$i] as $t
          | .hourly.dew_point_2m[$i] as $d
          | ($t - $d) <= $thr)
      ] | any
    '
); then
  log_error "Failed to parse forecast data for dew risk"
  exit 1
fi

# rain_risk: earliest hour today with any ( >0 ) precipitation probability
if ! rain_risk=$(
  printf '%s' "$data" | jq --arg today "$today" '
    def h($ts): ($ts[11:13] | tonumber);
    [ range(0; (.hourly.time|length)) as $i
      | .hourly.time[$i] as $ts
      | select($ts | startswith($today + "T"))
      | .hourly.precipitation_probability[$i] as $p
      | select($p > 0)
      | {ts:$ts, hour:h($ts), p:$p}
    ] | sort_by(.hour) | .[0] // null
  '
); then
  log_error "Failed to parse forecast data for rain risk"
  exit 1
fi

# heat_time: earliest hour today where temp >= cap
if ! heat_time=$(
  printf '%s' "$data" | jq --arg today "$today" --argjson cap "$TEMP_CAP_F" '
    def h($ts): ($ts[11:13] | tonumber);
    [ range(0; (.hourly.time|length)) as $i
      | .hourly.time[$i] as $ts
      | select($ts | startswith($today + "T"))
      | .hourly.temperature_2m[$i] as $t
      | select($t >= $cap)
      | {ts:$ts, hour:h($ts)}
    ] | sort_by(.hour) | .[0] // null
  '
); then
  log_error "Failed to parse forecast data for heat cap"
  exit 1
fi

dew_label="Dew: unlikely."
if [ "$dew_likely" = "true" ]; then
  dew_label="Dew: likely."
fi

rain_hour=""
rain_pct=""
if [ "$rain_risk" != "null" ]; then
  if ! rain_hour=$(printf '%s' "$rain_risk" | jq -r '.hour'); then
    log_error "Failed to read rain risk hour"
    exit 1
  fi
  if ! rain_pct=$(printf '%s' "$rain_risk" | jq -r '.p'); then
    log_error "Failed to read rain risk percent"
    exit 1
  fi
fi

heat_hour=""
if [ "$heat_time" != "null" ]; then
  if ! heat_hour=$(printf '%s' "$heat_time" | jq -r '.hour'); then
    log_error "Failed to read heat cap hour"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Decision audit logging
# ---------------------------------------------------------------------------
log_info "Thresholds: TEMP_CAP_F=$TEMP_CAP_F DEW_SPREAD_F=$DEW_SPREAD_F WORK_START_HOUR=$WORK_START_HOUR PRE_START_HOUR=$PRE_START_HOUR"
log_info "Computed dew_likely=$dew_likely"

if [ "$rain_risk" != "null" ]; then
  log_info "Computed rain_risk: hour=$rain_hour precip=${rain_pct}%"
else
  log_info "Computed rain_risk: none"
fi

if [ "$heat_time" != "null" ]; then
  log_info "Computed heat_time: hour=$heat_hour (>=${TEMP_CAP_F}F)"
else
  log_info "Computed heat_time: none"
fi

# Determine window end (earliest of rain risk and heat cap, if any)
window_msg=""
if [ -n "$rain_hour" ] && [ -n "$heat_hour" ]; then
  if [ "$rain_hour" -lt "$heat_hour" ]; then
    window_msg=$(printf '✅ Yard work window open until a %s%% chance of rain at %02d:00. %s' "$rain_pct" "$rain_hour" "$dew_label")
  elif [ "$heat_hour" -lt "$rain_hour" ]; then
    window_msg=$(printf '✅ Yard work window open until heat hits %s°F at %02d:00. %s' "$TEMP_CAP_F" "$heat_hour" "$dew_label")
  else
    window_msg=$(printf '✅ Yard work window open until %02d:00 (heat %s°F+ and %s%% rain risk). %s' "$heat_hour" "$TEMP_CAP_F" "$rain_pct" "$dew_label")
  fi
elif [ -n "$rain_hour" ]; then
  window_msg=$(printf '✅ Yard work window open until a %s%% chance of rain at %02d:00. %s' "$rain_pct" "$rain_hour" "$dew_label")
elif [ -n "$heat_hour" ]; then
  window_msg=$(printf '✅ Yard work window open until heat hits %s°F at %02d:00. %s' "$TEMP_CAP_F" "$heat_hour" "$dew_label")
else
  window_msg=$(printf '✅ Yard work window open all day. %s' "$dew_label")
fi

message=$window_msg

###############################################################################
# Update note (marker replacement)
###############################################################################
note_path="${daily_note_dir%/}/${today}.md"

if [ ! -f "$note_path" ]; then
  log_error "Daily note not found: $note_path"
  exit 1
fi

tmp="${TMPDIR:-/tmp}/yardwork.$$.tmp"
cleanup() { rm -f "$tmp" 2>/dev/null || true; }
trap cleanup EXIT INT HUP TERM

# Replace the marker once; keep the rest intact.
# (If the marker isn't present, the file will be unchanged.)
sed "s/<!-- yard-work-check -->/$message/" "$note_path" >"$tmp"

if cmp -s "$note_path" "$tmp"; then
  log_info "No update applied (marker missing or already up to date)"
  exit 0
fi

# Atomic-ish replace.
mv "$tmp" "$note_path" 2>/dev/null || {
  log_error "Failed to write updated note: $note_path"
  exit 1
}

# Ensure readable perms for downstream git user
chmod 664 "$note_path" 2>/dev/null || chmod 644 "$note_path" 2>/dev/null || true

log_info "Updated yard work suitability in: $note_path"

###############################################################################
# Artifact declaration (for wrapper commit orchestration)
###############################################################################
if [ -n "${COMMIT_LIST_FILE:-}" ]; then
  # Append only finalized artifacts.
  # Failure to append must be non-fatal; log a WARN.
  if ! printf '%s\n' "$note_path" >>"$COMMIT_LIST_FILE"; then
    log_warn "Failed to append artifact to COMMIT_LIST_FILE: $COMMIT_LIST_FILE"
  fi
fi

exit 0
