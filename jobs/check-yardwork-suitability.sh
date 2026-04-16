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
script_dir=$(CDPATH='' cd "$(dirname "$0")" && pwd -P)
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

periodic_notes_dir=${PERIODIC_NOTES_DIR:-Periodic Notes}
daily_note_dir="${vault_root}/${periodic_notes_dir}/Daily Notes"

###############################################################################
# Tunables
###############################################################################
LAT=47.7423
LON=-121.9857
TEMP_CAP_F=70           # "Too hot" at or above this temp
WORK_START_HOUR=8       # 08:00 local
PRE_START_HOUR=7        # 07:00 local
DEW_SPREAD_F=2          # Dew likely if (temp - dew point) <= this at 07:00 or 08:00

# Rain/dampness tunables (inches)
RAIN_HOURLY_IN=0.01     # "It's raining" if hourly precip >= this (1/100")
OVERNIGHT_SUM_IN=0.03   # Ground likely damp if precip sum from 00:00..PRE_START_HOUR >= this
OVERNIGHT_MAX_IN=0.02   # Or if any single hour overnight meets/exceeds this

# Forecast fetch hardening
CURL_RETRIES=3
CURL_RETRY_DELAY=2
CURL_CONNECT_TIMEOUT=10
CURL_MAX_TIME=30
RAIN_PROB_FLOOR=20      # Keep probability as context; used only to report/confirm

API_URL="https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&hourly=temperature_2m,dew_point_2m,precipitation,precipitation_probability&temperature_unit=fahrenheit&precipitation_unit=inch&timezone=America/Los_Angeles"

###############################################################################
# Fetch forecast data
###############################################################################
log_info "Fetching forecast from Open-Meteo"
fetch_err="${TMPDIR:-/tmp}/yardwork.fetch.$$.err"
fetch_ok=0
attempt=1

while [ "$attempt" -le "$CURL_RETRIES" ]; do
  : >"$fetch_err"

  if data=$(
    curl -fsS \
      --connect-timeout "$CURL_CONNECT_TIMEOUT" \
      --max-time "$CURL_MAX_TIME" \
      "$API_URL" 2>"$fetch_err"
  ); then
    fetch_ok=1
    break
  fi

  curl_rc=$?
  err_msg=$(tr '\n' ' ' <"$fetch_err" 2>/dev/null | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//')

  if [ -n "$err_msg" ]; then
    log_warn "Forecast fetch attempt $attempt/$CURL_RETRIES failed: curl rc=$curl_rc; $err_msg"
  else
    log_warn "Forecast fetch attempt $attempt/$CURL_RETRIES failed: curl rc=$curl_rc"
  fi

  if [ "$attempt" -lt "$CURL_RETRIES" ]; then
    log_info "Retrying forecast fetch in ${CURL_RETRY_DELAY}s"
    sleep "$CURL_RETRY_DELAY"
  fi

  attempt=$((attempt + 1))
done

rm -f "$fetch_err" 2>/dev/null || true

if [ "$fetch_ok" != "1" ]; then
  log_error "Failed to fetch forecast data from API after $CURL_RETRIES attempts"
  exit 1
fi

today=$(date +%Y-%m-%d)

###############################################################################
# Log raw decision inputs (for dew/rain/heat tuning visibility)
###############################################################################
log_info "Decision inputs for $today (hours $PRE_START_HOUR and $WORK_START_HOUR):"

inputs_err="${TMPDIR:-/tmp}/yardwork.inputs.$$.err"
inputs_out=""
if ! inputs_out=$(
  printf '%s' "$data" | jq -r \
    --arg today "$today" \
    --argjson h1 "$PRE_START_HOUR" \
    --argjson h2 "$WORK_START_HOUR" '
      def r1(x): ((x * 10 | round) / 10);
      range(0; (.hourly.time|length)) as $i
      | .hourly.time[$i] as $ts
      | select($ts | startswith($today + "T"))
      | ($ts[11:13] | tonumber) as $h
      | select($h == $h1 or $h == $h2)
      | .hourly.temperature_2m[$i] as $t
      | .hourly.dew_point_2m[$i] as $d
      | .hourly.precipitation_probability[$i] as $p
      | .hourly.precipitation[$i] as $q
      | (r1($t) as $tr
        | r1($d) as $dr
        | r1($t - $d) as $sr
        | "Hour \($h): temp=\($tr)F dew=\($dr)F spread=\($sr)F precip=\($p)% amount=\($q)in")
    ' 2>"$inputs_err"
); then
  # If jq fails, emit the captured error for observability.
  err_msg=$(tr '\n' ' ' <"$inputs_err" 2>/dev/null || true)
  log_warn "Decision inputs jq failed: $err_msg"
  rm -f "$inputs_err" 2>/dev/null || true
else
  rm -f "$inputs_err" 2>/dev/null || true
  if [ -z "$inputs_out" ]; then
    log_warn "Decision inputs: no matching hourly rows found for $today at hours $PRE_START_HOUR/$WORK_START_HOUR"
  else
    printf '%s\n' "$inputs_out" | while IFS= read -r line; do
      [ -n "$line" ] && log_info "$line"
    done
  fi
fi

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

# dampness: look at precip *before* PRE_START_HOUR to estimate wet ground at start
if ! damp=$(
  printf '%s' "$data" | jq --arg today "$today" \
    --argjson end "$PRE_START_HOUR" \
    --argjson sum_thr "$OVERNIGHT_SUM_IN" \
    --argjson max_thr "$OVERNIGHT_MAX_IN" '
    def h($ts): ($ts[11:13] | tonumber);
    def rows:
      [ range(0; (.hourly.time|length)) as $i
        | .hourly.time[$i] as $ts
        | select($ts | startswith($today + "T"))
        | (h($ts)) as $hh
        | select($hh < $end)
        | {hour:$hh,
           q:(.hourly.precipitation[$i] // 0),
           p:(.hourly.precipitation_probability[$i] // 0)}
      ];
    (rows) as $r
    | ($r | map(.q) | add) as $sum
    | ($r | map(.q) | max // 0) as $max
    | {sum_in:$sum,
       max_in:$max,
       damp_likely:(($sum >= $sum_thr) or ($max >= $max_thr))}
  '
); then
  log_error "Failed to parse forecast data for dampness risk"
  exit 1
fi

# rain_risk: first hour >= PRE_START_HOUR with measurable precip (amount-based)
if ! rain_risk=$(
  printf '%s' "$data" | jq --arg today "$today" \
    --argjson start "$PRE_START_HOUR" \
    --argjson qthr "$RAIN_HOURLY_IN" \
    --argjson pthr "$RAIN_PROB_FLOOR" '
    def h($ts): ($ts[11:13] | tonumber);
    [ range(0; (.hourly.time|length)) as $i
      | .hourly.time[$i] as $ts
      | select($ts | startswith($today + "T"))
      | (h($ts)) as $hh
      | select($hh >= $start)
      | (.hourly.precipitation[$i] // 0) as $q
      | (.hourly.precipitation_probability[$i] // 0) as $p
      | select($q >= $qthr)
      | {ts:$ts, hour:$hh, q:$q, p:$p, prob_meets:($p >= $pthr)}
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
  if ! rain_amt=$(printf '%s' "$rain_risk" | jq -r '.q'); then
    log_error "Failed to read rain risk amount"
    exit 1
  fi
  if ! rain_prob_meets=$(printf '%s' "$rain_risk" | jq -r '.prob_meets'); then
    log_error "Failed to read rain risk prob_meets"
    exit 1
  fi
fi

overnight_sum=$(printf '%s' "$damp" | jq -r '.sum_in')
overnight_max=$(printf '%s' "$damp" | jq -r '.max_in')
damp_likely=$(printf '%s' "$damp" | jq -r '.damp_likely')

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
  log_info "Computed rain_risk: hour=$rain_hour amount=${rain_amt}in precip=${rain_pct}% (prob_meets_floor=$rain_prob_meets)"
else
  log_info "Computed rain_risk: none"
fi

log_info "Computed dampness: damp_likely=$damp_likely overnight_sum=${overnight_sum}in overnight_max=${overnight_max}in (sum_thr=${OVERNIGHT_SUM_IN}in max_thr=${OVERNIGHT_MAX_IN}in)"

if [ "$heat_time" != "null" ]; then
  log_info "Computed heat_time: hour=$heat_hour (>=${TEMP_CAP_F}F)"
else
  log_info "Computed heat_time: none"
fi

# Determine window end (earliest of rain risk and heat cap, if any)
window_msg=""
if [ -n "$rain_hour" ] && [ -n "$heat_hour" ]; then
  if [ "$rain_hour" -lt "$heat_hour" ]; then
    window_msg=$(printf '✅ Yard work window open until rain at %02d:00 (%sin, %s%%). %s' "$rain_hour" "$rain_amt" "$rain_pct" "$dew_label")
  elif [ "$heat_hour" -lt "$rain_hour" ]; then
    window_msg=$(printf '✅ Yard work window open until heat hits %s°F at %02d:00. %s' "$TEMP_CAP_F" "$heat_hour" "$dew_label")
  else
    window_msg=$(printf '✅ Yard work window open until %02d:00 (heat %s°F+ and rain %sin/%s%%). %s' "$heat_hour" "$TEMP_CAP_F" "$rain_amt" "$rain_pct" "$dew_label")
  fi
elif [ -n "$rain_hour" ]; then
  window_msg=$(printf '✅ Yard work window open until rain at %02d:00 (%sin, %s%%). %s' "$rain_hour" "$rain_amt" "$rain_pct" "$dew_label")
elif [ -n "$heat_hour" ]; then
  window_msg=$(printf '✅ Yard work window open until heat hits %s°F at %02d:00. %s' "$TEMP_CAP_F" "$heat_hour" "$dew_label")
else
  window_msg=$(printf '✅ Yard work window open all day. %s' "$dew_label")
fi

if [ "$damp_likely" = "true" ]; then
  window_msg="$window_msg Ground: likely damp."
fi

# Append yardwork priorities link
yardwork_link="[[Annual Yardwork Priorities]]"
window_msg="$window_msg See: $yardwork_link"

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

# Escape replacement text for sed "s///" (avoid &, /, and \ surprises).
# Message is expected to be single-line.
sed_repl=$(
  printf '%s' "$message" \
    | sed -e 's/\\/\\\\/g' -e 's/[\/&]/\\&/g'
)

# Replace the marker once; keep the rest intact.
# (If the marker isn't present, the file will be unchanged.)
sed "s/<!-- yard-work-check -->/$sed_repl/" "$note_path" >"$tmp"

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
