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
TEMP_CAP_F=70          # Max acceptable temp for "good" conditions
EARLY_HOUR_START=0     # Inclusive (local time)
EARLY_HOUR_END=6       # Inclusive (local time)

API_URL="https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&hourly=temperature_2m,dew_point_2m&temperature_unit=fahrenheit&timezone=America/Los_Angeles"

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
# Evaluate suitability
###############################################################################
# early_unsuitable: any early-hour where temp < dew point
if ! early_unsuitable=$(
  printf '%s' "$data" | jq --arg today "$today" \
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
  log_error "Failed to parse forecast data for early hours"
  exit 1
fi

# high_temp_unsuitable: any hour today where temp >= cap
if ! high_temp_unsuitable=$(
  printf '%s' "$data" | jq --arg today "$today" --argjson cap "$TEMP_CAP_F" '
    [ range(0; (.hourly.time|length)) as $i
      | select(.hourly.time[$i] | startswith($today + "T"))
      | .hourly.temperature_2m[$i]
    ] | map(select(. >= $cap)) | length > 0
  '
); then
  log_error "Failed to parse forecast data for temperature cap"
  exit 1
fi

if [ "$early_unsuitable" = "true" ] || [ "$high_temp_unsuitable" = "true" ]; then
  message="❌ Not ideal for yard work today."
else
  message="✅ Good yard work conditions expected today."
fi

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
