#!/bin/sh
#
# sleep-summary.sh
#
# Generate a sleep summary markdown file for a given date.
# - Input:  "Sleep Data/YYYY-MM-DD.txt"
# - Output: "Sleep Data/YYYY-MM-DD Sleep Summary.md"
# - Flags:  -debug to enable verbose logging
#

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
utils_dir=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
job_wrap="$utils_dir/core/job-wrap.sh"
script_path="$script_dir/$(basename "$0")"

log_info() { printf 'INFO %s\n' "$*"; }
log_warn() { printf 'WARN %s\n' "$*" >&2; }
log_err() { printf 'ERR %s\n' "$*" >&2; }
log_debug() { [ "${LOG_DEBUG:-0}" -ne 0 ] && printf 'DEBUG %s\n' "$*"; }

if [ "${JOB_WRAP_ACTIVE:-0}" != "1" ] && [ -x "$job_wrap" ]; then
  JOB_WRAP_ACTIVE=1 exec /bin/sh "$job_wrap" "$script_path" "$@"
fi
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

: "${LOG_DEBUG:=0}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_err "missing required command: $1"
    exit 1
  fi
}

tmpfile() {
  mktemp "${TMPDIR:-/tmp}/sleep-summary.XXXXXX" 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/sleep-summary.$$"
}

###############################################################################
# Timestamp helpers & metadata parsing
###############################################################################

timestamp_to_epoch() {
  ts=$1
  [ -n "${ts:-}" ] || return 1

  log_debug "timestamp_to_epoch: raw='$ts'"

  nbsp=$(printf '\302\240')
  nnbsp=$(printf '\342\200\257')
  normalized=$(printf '%s' "$ts" \
    | tr -d '\r' \
    | sed -e "s/${nbsp}/ /g" -e "s/${nnbsp}/ /g")
  trimmed=$(printf '%s' "$normalized" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

  log_debug "timestamp_to_epoch: trimmed='$trimmed'"

  SLEEP_TZ=${SLEEP_TZ:-America/Los_Angeles}
  formats='%Y-%m-%dT%H:%M:%S%z|%Y-%m-%dT%H:%M:%S|%Y-%m-%dT%H:%M|%Y-%m-%d %H:%M:%S %z|%Y-%m-%d %H:%M:%S|%Y-%m-%d %H:%M|%b %d, %Y at %I:%M:%S %p|%b %d, %Y at %I:%M %p|%B %d, %Y at %I:%M:%S %p|%B %d, %Y at %I:%M %p'
  old_ifs=$IFS
  IFS='|'
  for fmt in $formats; do
    [ -z "$fmt" ] && continue

    case $fmt in
      *%z*)
        log_debug "timestamp_to_epoch: trying fmt='$fmt' (offset-aware, no TZ override)"
        if epoch=$(date -j -f "$fmt" "$trimmed" '+%s' 2>/dev/null); then
          # If format has no explicit seconds, floor to the minute.
          case "$fmt" in
            *%S*|*%T*) ;;  # has seconds, leave as-is
            *)
              adj=$((epoch - (epoch % 60)))
              log_debug "timestamp_to_epoch: fmt '$fmt' has no seconds; adjusting epoch from $epoch to $adj (floor to minute)"
              epoch=$adj
              ;;
          esac
          IFS=$old_ifs
          log_debug "timestamp_to_epoch: success fmt='$fmt' epoch=$epoch iso=$(date -u -r "$epoch" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"
          printf '%s\n' "$epoch"
          return 0
        fi
        ;;
      *)
        log_debug "timestamp_to_epoch: trying fmt='$fmt' (SLEEP_TZ=$SLEEP_TZ)"
        if epoch=$(TZ="$SLEEP_TZ" date -j -f "$fmt" "$trimmed" '+%s' 2>/dev/null); then
          # If format has no explicit seconds, floor to the minute.
          case "$fmt" in
            *%S*|*%T*) ;;  # has seconds, leave as-is
            *)
              adj=$((epoch - (epoch % 60)))
              log_debug "timestamp_to_epoch: fmt '$fmt' has no seconds; adjusting epoch from $epoch to $adj (floor to minute)"
              epoch=$adj
              ;;
          esac
          IFS=$old_ifs
          log_debug "timestamp_to_epoch: success fmt='$fmt' epoch=$epoch iso=$(date -u -r "$epoch" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"
          printf '%s\n' "$epoch"
          return 0
        fi
        ;;
    esac
  done
  IFS=$old_ifs
  log_warn "timestamp_to_epoch: FAILED to parse '$trimmed'"
  return 1
}

epoch_to_iso() {
  ep=$1
  if iso=$(date -u -r "$ep" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null); then
    printf '%s\n' "$iso"
    return 0
  fi
  printf '%s\n' "$ep"
}

format_duration_hms() {
  total_secs=$1
  h=$((total_secs / 3600))
  m=$(((total_secs % 3600) / 60))
  s=$((total_secs % 60))
  printf '%d:%02d:%02d\n' "$h" "$m" "$s"
}

split_sleep_file() {
  in_file=$1
  stage_out=$2
  meta_out=$3
  : >"$stage_out"
  : >"$meta_out"
  log_debug "split_sleep_file: splitting '$in_file' into data='$stage_out' and meta='$meta_out'"
  awk -v stage="$stage_out" -v meta="$meta_out" '
    BEGIN { meta_mode = 0 }
    /^[[:space:]]*#[[:space:]]*Wake Metadata[[:space:]]*$/ {
      meta_mode = 1
      next
    }
    {
      if (meta_mode) {
        print > meta
        next
      }
      if ($0 ~ /^[[:space:]]*[A-Za-z0-9_]+=.*/) {
        meta_mode = 1
        print > meta
      } else {
        print > stage
      }
    }
  ' "$in_file"
  data_count=$(wc -l <"$stage_out" | awk '{print $1}')
  meta_count=$(wc -l <"$meta_out" | awk '{print $1}')
  log_debug "split_sleep_file: data lines=$data_count meta lines=$meta_count"
}

read_wake_metadata_value() {
  meta_file=$1
  key=$2
  [ -f "$meta_file" ] || return 1
  log_debug "read_wake_metadata_value: scanning '$meta_file' for key='$key'"
  while IFS= read -r line; do
    case $line in
      ""|\#*) continue ;;
      $key=*)
        value=${line#${key}=}
        value=$(printf '%s' "$value" | tr -d '\r')
        log_debug "read_wake_metadata_value: found $key='$value'"
        printf '%s\n' "$value"
        return 0
        ;;
    esac
  done <"$meta_file"
  log_debug "read_wake_metadata_value: key='$key' not found in '$meta_file'"
  return 1
}

apply_wake_window() {
  entries_json=$1
  window_start=$2
  window_end=$3

  log_debug "apply_wake_window: window_start=$window_start iso=$(epoch_to_iso "$window_start") window_end=$window_end iso=$(epoch_to_iso "$window_end")"

  entries_tmp=$(tmpfile)
  printf '%s\n' "$entries_json" | jq -c '.[]' >"$entries_tmp"
  trimmed_tmp=$(tmpfile)
  trim_error=0

  total_entries=$(wc -l <"$entries_tmp" | awk '{print $1}')
  log_debug "apply_wake_window: total entries before trim=$total_entries"

  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    stage=$(printf '%s\n' "$entry" | jq -r '.stage')
    start_raw=$(printf '%s\n' "$entry" | jq -r '.start')
    end_raw=$(printf '%s\n' "$entry" | jq -r '.end')

    log_debug "apply_wake_window: entry stage='$stage' start_raw='$start_raw' end_raw='$end_raw'"

    start_epoch=$(timestamp_to_epoch "$start_raw" || true)
    end_epoch=$(timestamp_to_epoch "$end_raw" || true)

    if [ -z "${start_epoch:-}" ] || [ -z "${end_epoch:-}" ]; then
      log_warn "apply_wake_window: FAILED to parse epochs for stage='$stage' start='$start_raw' end='$end_raw'"
      trim_error=1
      break
    fi

    log_debug "apply_wake_window: stage='$stage' start_epoch=$start_epoch iso=$(epoch_to_iso "$start_epoch") end_epoch=$end_epoch iso=$(epoch_to_iso "$end_epoch")"

    # invalid or zero-length interval?
    if [ "$end_epoch" -le "$start_epoch" ]; then
      log_debug "apply_wake_window: DROP stage='$stage' reason=end<=start start_ep=$start_epoch end_ep=$end_epoch"
      continue
    fi

    # entirely before window
    if [ "$end_epoch" -le "$window_start" ]; then
      log_debug "apply_wake_window: DROP stage='$stage' reason=before_window start_ep=$start_epoch end_ep=$end_epoch ws=$window_start we=$window_end"
      continue
    fi

    # entirely after window
    if [ "$start_epoch" -ge "$window_end" ]; then
      log_debug "apply_wake_window: DROP stage='$stage' reason=after_window start_ep=$start_epoch end_ep=$end_epoch ws=$window_start we=$window_end"
      continue
    fi

    clip_start=$start_epoch
    clip_end=$end_epoch
    if [ "$clip_start" -lt "$window_start" ]; then
      log_debug "apply_wake_window: stage='$stage' clip_start adjusted from $clip_start to window_start=$window_start"
      clip_start=$window_start
    fi
    if [ "$clip_end" -gt "$window_end" ]; then
      log_debug "apply_wake_window: stage='$stage' clip_end adjusted from $clip_end to window_end=$window_end"
      clip_end=$window_end
    fi

    overlap=$((clip_end - clip_start))
    if [ "$overlap" -le 0 ]; then
      log_debug "apply_wake_window: DROP stage='$stage' reason=no_overlap start_ep=$start_epoch end_ep=$end_epoch ws=$window_start we=$window_end clip_start=$clip_start clip_end=$clip_end"
      continue
    fi

    duration_sec=$overlap
    duration_min=$(printf '%s\n' "$duration_sec" | awk 'BEGIN{OFMT="%.10f"} {print $1 / 60}')
    duration_fmt=$(format_duration_hms "$duration_sec")

    start_fmt=$start_raw
    end_fmt=$end_raw
    if [ "$clip_start" -ne "$start_epoch" ]; then
      start_fmt=$(epoch_to_iso "$clip_start")
    fi
    if [ "$clip_end" -ne "$end_epoch" ]; then
      end_fmt=$(epoch_to_iso "$clip_end")
    fi

    log_debug "apply_wake_window: KEEP stage='$stage' overlap=${overlap}s durationMin=$duration_min start_fmt='$start_fmt' end_fmt='$end_fmt'"

    updated=$(printf '%s\n' "$entry" | jq \
      --arg start "$start_fmt" \
      --arg end "$end_fmt" \
      --arg duration "$duration_fmt" \
      --argjson durationMin "$duration_min" '
        .start = $start
        | .end = $end
        | .duration = $duration
        | .durationMin = $durationMin
      ')
    printf '%s\n' "$updated" >>"$trimmed_tmp"
  done <"$entries_tmp"

  rm -f "$entries_tmp"

  if [ "$trim_error" -ne 0 ]; then
    log_warn "apply_wake_window: trim_error=1, aborting without trimmed entries"
    rm -f "$trimmed_tmp"
    return 1
  fi

  trimmed_count=$(wc -l <"$trimmed_tmp" | awk '{print $1}')
  log_debug "apply_wake_window: entries after trim=$trimmed_count (removed=$((total_entries - trimmed_count)))"

  trimmed=$(jq -s '.' "$trimmed_tmp")
  rm -f "$trimmed_tmp"
  printf '%s\n' "$trimmed"
  return 0
}

require_cmd jq
require_cmd bc
require_cmd paste
require_cmd date

###############################################################################
# Paths & helpers
###############################################################################

date_helpers="$utils_dir/core/date-period-helpers.sh"

# shellcheck source=../core/date-period-helpers.sh
. "$date_helpers"

vaultRoot="${VAULT_PATH:-$HOME/vaults/Main}"
sleepFolder="$vaultRoot/Sleep Data"

explicit_date=""
while [ "$#" -gt 0 ]; do
  case $1 in
    -debug)
      LOG_DEBUG=1
      shift
      ;;
    -*)
      log_err "unknown option: $1"
      exit 1
      ;;
    *)
      explicit_date=$1
      shift
      ;;
  esac
done

# Optional arg: explicit date (YYYY-MM-DD). Default: get_today.
target_date="${explicit_date:-$(get_today)}"

inputPath="$sleepFolder/$target_date.txt"
outputPath="$sleepFolder/$target_date Sleep Summary.md"

log_info "summarizing sleep for $target_date"
log_info "input: $inputPath"
log_info "output: $outputPath"

if [ ! -f "$inputPath" ]; then
  log_err "no input file for $target_date"
  exit 1
fi

stage_block=$(tmpfile)
meta_block=$(tmpfile)
split_sleep_file "$inputPath" "$stage_block" "$meta_block"

###############################################################################
# Helpers
###############################################################################

raw_to_entries() {
  jq -R -s '
    (split("\n") | map(select(length > 0))) as $l |
    ($l | length) as $len |
    if ($len % 4) != 0 then
      error("sleep data line count not divisible by 4: \($len)")
    else
      ($len / 4 | floor) as $q |
      [ range(0; $q)
        | {
            stage:    $l[.],
            duration: $l[. + $q],
            start:    $l[. + 2 * $q],
            end:      $l[. + 3 * $q]
          }
      ]
    end
  '
}

jq_add_duration_min_filter='
  def toMinutes($d):
    ($d | split(":")) as $p |
    if   ($p | length) == 3 then ($p[0] | tonumber) * 60 + ($p[1] | tonumber) + ($p[2] | tonumber) / 60
    elif ($p | length) == 2 then ($p[0] | tonumber)      + ($p[1] | tonumber) / 60
    elif ($p | length) == 1 then ($p[0] | tonumber) / 60
    else 0 end;
  map(.durationMin = toMinutes(.duration))
'

process_date() {
  ds="$1"
  file="$sleepFolder/$ds.txt"
  [ -f "$file" ] || return

  log_debug "process_date: ds=$ds file='$file'"

  stage_tmp=$(tmpfile)
  meta_tmp=$(tmpfile)
  split_sleep_file "$file" "$stage_tmp" "$meta_tmp"

  err_file=$(tmpfile)
  if ! entries=$(raw_to_entries < "$stage_tmp" | jq "$jq_add_duration_min_filter" 2>"$err_file"); then
    err=$(cat "$err_file")
    rm -f "$err_file"
    rm -f "$stage_tmp" "$meta_tmp"
    log_warn "process_date: failed to process $file: ${err:-jq parsing error}"
    return 1
  fi
  rm -f "$err_file" "$stage_tmp"

  entry_count=$(printf '%s\n' "$entries" | jq 'length')
  log_debug "process_date: initial entry_count=$entry_count"

  untrimmedMin=$(printf '%s\n' "$entries" | jq '[ .[] | select(.stage != "Awake") | .durationMin ] | add // 0')
  log_debug "process_date: UNTRIMMED_SLEEP_MIN=$untrimmedMin"

  y_meta=$(read_wake_metadata_value "$meta_tmp" "YESTERDAY_WAKE" || true)
  t_meta=$(read_wake_metadata_value "$meta_tmp" "TODAY_WAKE" || true)

  if [ -z "${y_meta:-}" ] || [ -z "${t_meta:-}" ]; then
    log_err "process_date: missing wake metadata for ds=$ds (Y=${y_meta:-unset}, T=${t_meta:-unset})"
    rm -f "$meta_tmp"
    return 1
  fi

  if ! y_epoch=$(timestamp_to_epoch "$y_meta"); then
    log_err "process_date: failed to parse YESTERDAY_WAKE for ds=$ds raw='$y_meta'"
    rm -f "$meta_tmp"
    return 1
  fi

  if ! t_epoch=$(timestamp_to_epoch "$t_meta"); then
    log_err "process_date: failed to parse TODAY_WAKE for ds=$ds raw='$t_meta'"
    rm -f "$meta_tmp"
    return 1
  fi

  log_debug "process_date: y_meta='$y_meta' y_epoch=$y_epoch t_meta='$t_meta' t_epoch=$t_epoch"

  if [ "$t_epoch" -le "$y_epoch" ]; then
    log_err "process_date: invalid wake window order for ds=$ds (y='$y_meta' t='$t_meta')"
    rm -f "$meta_tmp"
    return 1
  fi

  entries_before=$(printf '%s\n' "$entries" | jq 'length')
  if ! trimmed=$(apply_wake_window "$entries" "$y_epoch" "$t_epoch"); then
    log_err "process_date: failed to apply wake window for ds=$ds"
    rm -f "$meta_tmp"
    return 1
  fi

  entries=$trimmed
  entries_after=$(printf '%s\n' "$entries" | jq 'length')
  log_debug "process_date: applied wake window ds=$ds entries_before=$entries_before entries_after=$entries_after"

  rm -f "$meta_tmp"

  minutes=$(printf '%s\n' "$entries" | jq '
      [ .[] | select(.stage != "Awake") | .durationMin ]
      | add // empty
    ')
  log_debug "process_date: FINAL_SLEEP_MIN(ds=$ds)=$minutes"
  printf '%s\n' "$minutes"
}

###############################################################################
# Load entries for target_date & compute totals
###############################################################################

entries_err=$(tmpfile)
if ! entries=$(
  raw_to_entries < "$stage_block" | jq "$jq_add_duration_min_filter" 2>"$entries_err"
); then
  err=$(cat "$entries_err")
  rm -f "$entries_err" "$stage_block" "$meta_block"
  log_err "failed to parse $inputPath: ${err:-jq parsing error}"
  exit 1
fi
rm -f "$entries_err"

entry_count_main=$(printf '%s\n' "$entries" | jq 'length')
log_debug "main: initial entry_count=$entry_count_main"

untrimmedSleepMin=$(
  printf '%s\n' "$entries" | jq '
    [ .[] | select(.stage != "Awake") | .durationMin ] | add // 0
  '
)
log_debug "main: UNTRIMMED_SLEEP_MIN=$untrimmedSleepMin"

yesterday_wake_raw=${YESTERDAY_WAKE:-}
today_wake_raw=${TODAY_WAKE:-}

if [ -z "${yesterday_wake_raw:-}" ]; then
  yesterday_wake_raw=$(read_wake_metadata_value "$meta_block" "YESTERDAY_WAKE" || true)
fi
if [ -z "${today_wake_raw:-}" ]; then
  today_wake_raw=$(read_wake_metadata_value "$meta_block" "TODAY_WAKE" || true)
fi

log_debug "main: yesterday_wake_raw='${yesterday_wake_raw:-}' today_wake_raw='${today_wake_raw:-}'"

if [ -z "${yesterday_wake_raw:-}" ] || [ -z "${today_wake_raw:-}" ]; then
  log_err "missing wake timestamps for target date (Y=${yesterday_wake_raw:-unset}, T=${today_wake_raw:-unset})"
  rm -f "$stage_block" "$meta_block"
  exit 1
fi

if ! yesterday_epoch=$(timestamp_to_epoch "$yesterday_wake_raw"); then
  log_err "failed to parse YESTERDAY_WAKE for target date raw='${yesterday_wake_raw:-}'"
  rm -f "$stage_block" "$meta_block"
  exit 1
fi

if ! today_epoch=$(timestamp_to_epoch "$today_wake_raw"); then
  log_err "failed to parse TODAY_WAKE for target date raw='${today_wake_raw:-}'"
  rm -f "$stage_block" "$meta_block"
  exit 1
fi

log_debug "main: yesterday_epoch=$yesterday_epoch today_epoch=$today_epoch"

if [ "$today_epoch" -le "$yesterday_epoch" ]; then
  log_err "invalid wake window (${yesterday_wake_raw:-?} to ${today_wake_raw:-?})"
  rm -f "$stage_block" "$meta_block"
  exit 1
fi

before_count=$(printf '%s\n' "$entries" | jq 'length')
if ! trimmed_entries=$(apply_wake_window "$entries" "$yesterday_epoch" "$today_epoch"); then
  log_err "failed to trim entries with wake window for target date"
  rm -f "$stage_block" "$meta_block"
  exit 1
fi

entries=$trimmed_entries
after_count=$(printf '%s\n' "$entries" | jq 'length')
removed=$((before_count - after_count))
log_debug "applied wake window: ${yesterday_wake_raw} (${yesterday_epoch}) → ${today_wake_raw} (${today_epoch}) | trimmed ${removed} entrie(s)"

rm -f "$stage_block" "$meta_block"

# Total minutes of sleep excluding "Awake"
totalMin=$(
  printf '%s\n' "$entries" | jq '
    [ .[] | select(.stage != "Awake") | .durationMin ] | add // 0
  '
)

log_debug "main: FINAL_SLEEP_MIN(totalMin)=$totalMin"

totalH=$(printf '%s\n' "$totalMin" | awk '{printf("%d", $1 / 60)}')
totalM=$(printf '%s %s\n' "$totalMin" "$totalH" | awk '{m = $1 - $2 * 60; printf("%.0f", m)}')

# Per-stage summary lines (for bullet list)
stageLines=$(
  printf '%s\n' "$entries" | jq -r '
    group_by(.stage)
    | map({ stage: .[0].stage, mins: (map(.durationMin) | add) })
    | .[]
    | [ .stage, (.mins | tostring) ]
    | @tsv
  '
)

# Full entries (for detailed list at the bottom)
entriesLines=$(
  printf '%s\n' "$entries" | jq -r '
    .[] | [ .stage, (.durationMin | tostring), .start, .end ] | @tsv
  '
)

###############################################################################
# 7-day running average (up to last 7 days with data, incl. target_date)
###############################################################################

pastTotals_file=$(tmpfile)
: >"$pastTotals_file"
for offset in 6 5 4 3 2 1 0; do
  day_offset=$((0 - offset))
  d=$(shift_utc_date_by_days "$target_date" "$day_offset")
  log_debug "main: computing process_date for d=$d (offset=$day_offset)"
  if ! t=$(process_date "$d"); then
    log_err "main: failed process_date for d=$d"
    rm -f "$pastTotals_file"
    exit 1
  fi
  if [ -n "${t:-}" ]; then
    log_debug "main: process_date d=$d returned t=$t"
    printf '%s\n' "$t" >>"$pastTotals_file"
  else
    log_debug "main: process_date d=$d returned empty"
  fi
done

cleanTotals=$(sed '/^$/d' "$pastTotals_file")
rm -f "$pastTotals_file"
count=$(printf '%s\n' "$cleanTotals" | wc -l | awk '{print $1}')
log_debug "main: 7-day window count=$count totals='$cleanTotals'"

if [ "$count" -gt 0 ]; then
  bc_err=$(tmpfile)
  if ! sum7=$(printf '%s\n' "$cleanTotals" | paste -sd+ - | bc -l 2>"$bc_err"); then
    err=$(cat "$bc_err")
    rm -f "$bc_err"
    log_err "failed to compute running average with bc: ${err:-bc error (no stderr captured)}"
    exit 1
  else
    rm -f "$bc_err"
    avgMin=$(printf '%s\n' "$sum7" | awk -v c="$count" 'BEGIN{OFMT="%.4f"} {print $1 / c}')
  fi
else
  avgMin=0
fi

log_debug "main: 7-day running average avgMin=$avgMin"

avgH=$(printf '%s\n' "$avgMin" | awk '{printf("%d", $1 / 60)}')
avgM=$(printf '%s %s\n' "$avgMin" "$avgH" | awk '{m = $1 - $2 * 60; printf("%.0f", m)}')

###############################################################################
# Sleep advice based on last night + 7-day running average
###############################################################################

# Hours with one decimal, for human-readable text
totalH_dec=$(printf '%s\n' "$totalMin" | awk 'BEGIN{OFMT="%.1f"} {print $1 / 60}')
avgH_dec=$(printf '%s\n' "$avgMin" | awk 'BEGIN{OFMT="%.1f"} {print $1 / 60}')

# Thresholds in minutes (using ideal = 8h, decisions in hour-based bands)
# Last night overrides:
#   < 5.5h (330 min)  -> disable alarms
#   < 6.0h (360 min)  -> sleep in ~2h next suitable morning
# Otherwise base on 7-day avg:
#   avg < 6.0h (360)  -> very low
#   6.0–6.7h (360–402)-> low
#   6.7–7.3h (402–438)-> slightly low
#   >= 7.3h (>=438)   -> fine

sleep_advice_reason=""
sleep_advice="Your 7-day running average is close to your 8-hour target. No catch-up sleep is needed; stick to your normal wake time."

# Strong last-night overrides first
if [ "$(printf '%s < %s\n' "$totalMin" "330" | bc -l)" -eq 1 ]; then
  sleep_advice_reason="last_night_very_short"
  sleep_advice=$(printf '%s\n' \
    "Last night was about ${totalH_dec} hours, which is very short." \
    "When possible, disable alarms and sleep until you naturally wake to catch up.")
elif [ "$(printf '%s < %s\n' "$totalMin" "360" | bc -l)" -eq 1 ]; then
  sleep_advice_reason="last_night_short"
  sleep_advice=$(printf '%s\n' \
    "Last night was about ${totalH_dec} hours, which is shorter than you’d like." \
    "Plan to sleep in for around 2 extra hours on your next suitable morning.")
else
  # No severe short night; use the 7-day running average
  if [ "$(printf '%s < %s\n' "$avgMin" "360" | bc -l)" -eq 1 ]; then
    sleep_advice_reason="avg_very_low"
    sleep_advice=$(printf '%s\n' \
      "Your 7-day running average is about ${avgH_dec} hours, which is very low compared to your 8-hour target." \
      "When you can, disable alarms and let yourself sleep as late as your schedule allows.")
  elif [ "$(printf '%s < %s\n' "$avgMin" "402" | bc -l)" -eq 1 ]; then
    sleep_advice_reason="avg_low"
    sleep_advice=$(printf '%s\n' \
      "Your 7-day running average is about ${avgH_dec} hours, which is low." \
      "Plan to sleep in for about 2 extra hours on your next off day.")
  elif [ "$(printf '%s < %s\n' "$avgMin" "438" | bc -l)" -eq 1 ]; then
    sleep_advice_reason="avg_slightly_low"
    sleep_advice=$(printf '%s\n' \
      "Your 7-day running average is about ${avgH_dec} hours, a bit under your 8-hour target." \
      "A 1-hour sleep-in is optional if you feel you need it.")
  else
    sleep_advice_reason="avg_ok"
    sleep_advice=$(printf '%s\n' \
      "Your 7-day running average is about ${avgH_dec} hours, close to your 8-hour target." \
      "No catch-up sleep is needed; stick to your normal wake time.")
  fi
fi

log_debug "main: sleep_advice_reason=$sleep_advice_reason totalMin=$totalMin avgMin=$avgMin"
log_debug "main: sleep_advice=$(printf '%s' "$sleep_advice" | tr '\n' '|' )"

###############################################################################
# Build markdown
###############################################################################

prev=$(shift_utc_date_by_days "$target_date" -1)
next=$(shift_utc_date_by_days "$target_date" 1)

linkLine="[[${prev} Sleep Summary|← ${prev} Sleep Summary]] | [[${next} Sleep Summary|${next} Sleep Summary →]]"

md=$(cat <<EOF
${linkLine}

## Sleep Summary for ${target_date}

🛌 Total (excl. Awake): ${totalH}h ${totalM}m (${totalMin} min)

📈 7-day running average: ${avgH}h ${avgM}m (${avgMin} min)

### Sleep Advice
${sleep_advice}

### By Stage:
EOF
)

log_info "total minutes (excl. Awake): $totalMin"
log_info "7-day running average (minutes): $avgMin"

while IFS="$(printf '\t')" read -r stage mins; do
  [ -z "$stage" ] && continue
  sh=$(printf '%s\n' "$mins" | awk '{printf("%d", $1 / 60)}')
  sm=$(printf '%s %s\n' "$mins" "$sh" | awk '{m = $1 - $2 * 60; printf("%.0f", m)}')
  md=$(printf '%s\n- %s: %sh %sm (%s min)' "$md" "$stage" "$sh" "$sm" "$mins")
done <<EOF
$stageLines
EOF

md=$(printf '%s\n---\n\n### Full Entries\n' "$md")
while IFS="$(printf '\t')" read -r stage mins start end; do
  [ -z "$stage" ] && continue
  stage_fmt=$(printf '%-6s' "$stage")
  md=$(printf '%s\n- %s | %s min | %s → %s' "$md" "$stage_fmt" "$mins" "$start" "$end")
done <<EOF
$entriesLines
EOF

###############################################################################
# Write file
###############################################################################

printf '%s\n' "$md" > "$outputPath"
log_info "wrote $(basename "$outputPath")"
