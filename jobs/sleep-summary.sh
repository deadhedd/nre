#!/bin/sh
#
# jobs/sleep-summary.sh
#
# Generate a sleep summary markdown file for a given date.
# - Input:  "Sleep Data/YYYY-MM-DD.txt"
# - Output: "Sleep Data/YYYY-MM-DD Sleep Summary.md"
#
# Leaf job (wrapper required)
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
# Resolve paths
###############################################################################

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
wrap="$script_dir/../engine/wrap.sh"

case "$0" in
  /*) script_path=$0 ;;
  *)  script_path=$script_dir/${0##*/} ;;
esac

script_path=$(
  CDPATH= cd "$(dirname "$script_path")" && \
  d=$(pwd) && \
  printf '%s/%s\n' "$d" "${script_path##*/}"
) || {
  log_error "failed to canonicalize script path: $script_path"
  exit 127
}

###############################################################################
# Self-wrap (minimal, dumb, contract-aligned)
###############################################################################

if [ "${JOB_WRAP_ACTIVE:-0}" != "1" ]; then
  if [ ! -x "$wrap" ]; then
    log_error "leaf wrap: wrapper not found/executable: $wrap"
    exit 127
  fi
  log_info "leaf wrap: exec wrapper: $wrap"
  exec "$wrap" "$script_path" ${1+"$@"}
else
  log_debug "leaf wrap: wrapper active; executing leaf"
fi

###############################################################################
# Cadence declaration (contract-required)
###############################################################################

JOB_CADENCE=${JOB_CADENCE:-daily}
log_info "cadence=$JOB_CADENCE"

###############################################################################
# Engine libs (wrapped path only)
###############################################################################

if [ -z "${REPO_ROOT:-}" ]; then
  log_error "REPO_ROOT not set (wrapper required)"
  exit 127
fi
case "$REPO_ROOT" in
  /*) : ;;
  *) log_error "REPO_ROOT not absolute: $REPO_ROOT"; exit 127 ;;
esac
repo_root=$REPO_ROOT

lib_dir=$repo_root/engine/lib
periods_lib=$lib_dir/periods.sh
datetime_lib=$lib_dir/datetime.sh

if [ ! -r "$periods_lib" ]; then
  log_error "periods lib not found/readable: $periods_lib"
  exit 127
fi
# shellcheck source=/dev/null
. "$periods_lib" || { log_error "failed to source periods lib: $periods_lib"; exit 127; }

if [ ! -r "$datetime_lib" ]; then
  log_error "datetime lib not found/readable: $datetime_lib"
  exit 127
fi
# shellcheck source=/dev/null
. "$datetime_lib" || { log_error "failed to source datetime lib: $datetime_lib"; exit 127; }

###############################################################################
# Minimal utility helpers
###############################################################################

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_error "missing required command: $1"
    exit 127
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

  nbsp=$(printf '\302\240')
  nnbsp=$(printf '\342\200\257')
  normalized=$(printf '%s' "$ts" \
    | tr -d '\r' \
    | sed -e "s/${nbsp}/ /g" -e "s/${nnbsp}/ /g")
  trimmed=$(printf '%s' "$normalized" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

  SLEEP_TZ=${SLEEP_TZ:-America/Los_Angeles}
  formats='%Y-%m-%dT%H:%M:%S%z|%Y-%m-%dT%H:%M:%S|%Y-%m-%dT%H:%M|%Y-%m-%d %H:%M:%S %z|%Y-%m-%d %H:%M:%S|%Y-%m-%d %H:%M|%b %d, %Y at %I:%M:%S %p|%b %d, %Y at %I:%M %p|%B %d, %Y at %I:%M:%S %p|%B %d, %Y at %I:%M %p'
  old_ifs=$IFS
  IFS='|'
  for fmt in $formats; do
    [ -z "$fmt" ] && continue
    case $fmt in
      *%z*)
        if epoch=$(date -j -f "$fmt" "$trimmed" '+%s' 2>/dev/null); then
          case "$fmt" in
            *%S*|*%T*) : ;;
            *) epoch=$((epoch - (epoch % 60))) ;;
          esac
          IFS=$old_ifs
          printf '%s\n' "$epoch"
          return 0
        fi
        ;;
      *)
        if epoch=$(TZ="$SLEEP_TZ" date -j -f "$fmt" "$trimmed" '+%s' 2>/dev/null); then
          case "$fmt" in
            *%S*|*%T*) : ;;
            *) epoch=$((epoch - (epoch % 60))) ;;
          esac
          IFS=$old_ifs
          printf '%s\n' "$epoch"
          return 0
        fi
        ;;
    esac
  done
  IFS=$old_ifs
  log_warn "timestamp_to_epoch: failed to parse: $trimmed"
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
  awk -v stage="$stage_out" -v meta="$meta_out" '
    BEGIN { meta_mode = 0 }
    /^[[:space:]]*#[[:space:]]*Wake Metadata[[:space:]]*$/ { meta_mode = 1; next }
    {
      if (meta_mode) { print > meta; next }
      if ($0 ~ /^[[:space:]]*[A-Za-z0-9_]+=.*/) { meta_mode = 1; print > meta }
      else { print > stage }
    }
  ' "$in_file"
}

read_wake_metadata_value() {
  meta_file=$1
  key=$2
  [ -f "$meta_file" ] || return 1
  while IFS= read -r line; do
    case $line in
      ""|\#*) continue ;;
      $key=*)
        value=${line#${key}=}
        value=$(printf '%s' "$value" | tr -d '\r')
        printf '%s\n' "$value"
        return 0
        ;;
    esac
  done <"$meta_file"
  return 1
}

apply_wake_window() {
  entries_json=$1
  window_start=$2
  window_end=$3

  entries_tmp=$(tmpfile)
  printf '%s\n' "$entries_json" | jq -c '.[]' >"$entries_tmp"
  trimmed_tmp=$(tmpfile)
  trim_error=0

  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    stage=$(printf '%s\n' "$entry" | jq -r '.stage')
    start_raw=$(printf '%s\n' "$entry" | jq -r '.start')
    end_raw=$(printf '%s\n' "$entry" | jq -r '.end')

    start_epoch=$(timestamp_to_epoch "$start_raw" || true)
    end_epoch=$(timestamp_to_epoch "$end_raw" || true)
    if [ -z "${start_epoch:-}" ] || [ -z "${end_epoch:-}" ]; then
      log_warn "apply_wake_window: failed to parse stage=$stage start=$start_raw end=$end_raw"
      trim_error=1
      break
    fi

    if [ "$end_epoch" -le "$start_epoch" ]; then
      continue
    fi
    if [ "$end_epoch" -le "$window_start" ]; then
      continue
    fi
    if [ "$start_epoch" -ge "$window_end" ]; then
      continue
    fi

    clip_start=$start_epoch
    clip_end=$end_epoch
    if [ "$clip_start" -lt "$window_start" ]; then clip_start=$window_start; fi
    if [ "$clip_end" -gt "$window_end" ]; then clip_end=$window_end; fi

    overlap=$((clip_end - clip_start))
    if [ "$overlap" -le 0 ]; then
      continue
    fi

    duration_sec=$overlap
    duration_min=$(printf '%s\n' "$duration_sec" | awk 'BEGIN{OFMT="%.10f"} {print $1 / 60}')
    duration_fmt=$(format_duration_hms "$duration_sec")

    start_fmt=$start_raw
    end_fmt=$end_raw
    if [ "$clip_start" -ne "$start_epoch" ]; then start_fmt=$(epoch_to_iso "$clip_start"); fi
    if [ "$clip_end" -ne "$end_epoch" ]; then end_fmt=$(epoch_to_iso "$clip_end"); fi

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
    rm -f "$trimmed_tmp"
    return 1
  fi

  trimmed=$(jq -s '.' "$trimmed_tmp")
  rm -f "$trimmed_tmp"
  printf '%s\n' "$trimmed"
  return 0
}

###############################################################################
# Requirements
###############################################################################

require_cmd jq
require_cmd bc
require_cmd paste
require_cmd date
require_cmd awk
require_cmd sed
require_cmd tr
require_cmd wc

###############################################################################
# Argument parsing
###############################################################################

usage() {
  cat <<'EOF_USAGE'
Usage: sleep-summary.sh [--output <path>] [--dry-run] [--force] [--debug] [YYYY-MM-DD]

Options:
  --output <path>  Write output to this path (overrides default in vault).
  --dry-run        Emit markdown to stdout instead of writing a file.
  --force          Allow overwrite when --output points to an existing file.
  --debug          Emit additional DEBUG lines to stderr.

Notes:
- If YYYY-MM-DD is omitted, defaults to today's local date.
EOF_USAGE
}

output_path=""
dry_run=0
force=0
debug=0
explicit_date=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --output)
      [ "$#" -ge 2 ] || { log_error "missing value for --output"; exit 2; }
      output_path=$2
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --force)
      force=1
      shift
      ;;
    --debug|-debug)
      debug=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -*)
      log_error "unknown option: $1"
      usage >&2
      exit 2
      ;;
    *)
      if [ -n "$explicit_date" ]; then
        log_error "unexpected extra arg: $1"
        usage >&2
        exit 2
      fi
      explicit_date=$1
      shift
      ;;
  esac
done

if [ "$debug" -eq 0 ]; then
  log_debug() { :; }
fi

target_date=${explicit_date:-$(dt_today_local)}

# Basic validation (strict YYYY-MM-DD)
dt_check_ymd "$target_date" >/dev/null 2>&1 || { log_error "invalid date: $target_date"; exit 2; }

###############################################################################
# Paths
###############################################################################

vault_root=${VAULT_PATH:-$HOME/vaults/Main}
case "$vault_root" in
  /*) : ;;
  *) vault_root=$(
       CDPATH= cd "$vault_root" 2>/dev/null && pwd -P
     ) || { log_error "failed to resolve VAULT_PATH: $vault_root"; exit 10; }
     ;;
esac

sleep_folder="$vault_root/Sleep Data"

input_path="$sleep_folder/$target_date.txt"
default_output="$sleep_folder/$target_date Sleep Summary.md"

if [ -n "$output_path" ]; then
  # If user provided a relative output, make it absolute relative to cwd.
  case "$output_path" in
    /*) : ;;
    *) output_path=$(
         d=$(pwd -P) && printf '%s/%s\n' "$d" "$output_path"
       ) || { log_error "failed to resolve --output: $output_path"; exit 10; }
       ;;
  esac
  final_output=$output_path
else
  final_output=$default_output
fi

log_info "summarizing sleep for $target_date"
log_info "input: $input_path"
log_info "output: $final_output"

if [ ! -f "$input_path" ]; then
  log_error "no input file for date: $target_date"
  exit 1
fi

if [ "$dry_run" -eq 0 ] && [ -f "$final_output" ] && [ "$force" -eq 0 ]; then
  # Default path overwrite is expected; but if user explicitly set --output, require --force.
  if [ -n "$output_path" ]; then
    log_error "output exists (use --force): $final_output"
    exit 1
  fi
fi

###############################################################################
# Parsing helpers
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
  ds=$1
  file="$sleep_folder/$ds.txt"
  [ -f "$file" ] || return 0

  stage_tmp=$(tmpfile)
  meta_tmp=$(tmpfile)
  split_sleep_file "$file" "$stage_tmp" "$meta_tmp"

  err_file=$(tmpfile)
  if ! entries=$(raw_to_entries <"$stage_tmp" | jq "$jq_add_duration_min_filter" 2>"$err_file"); then
    err=$(cat "$err_file" 2>/dev/null || true)
    rm -f "$err_file" "$stage_tmp" "$meta_tmp"
    log_warn "process_date: failed to parse $file: ${err:-jq parsing error}"
    return 1
  fi
  rm -f "$err_file" "$stage_tmp"

  y_meta=$(read_wake_metadata_value "$meta_tmp" "YESTERDAY_WAKE" || true)
  t_meta=$(read_wake_metadata_value "$meta_tmp" "TODAY_WAKE" || true)
  if [ -z "${y_meta:-}" ] || [ -z "${t_meta:-}" ]; then
    rm -f "$meta_tmp"
    log_warn "process_date: missing wake metadata for ds=$ds"
    return 1
  fi

  y_epoch=$(timestamp_to_epoch "$y_meta" || true)
  t_epoch=$(timestamp_to_epoch "$t_meta" || true)
  if [ -z "${y_epoch:-}" ] || [ -z "${t_epoch:-}" ] || [ "$t_epoch" -le "$y_epoch" ]; then
    rm -f "$meta_tmp"
    log_warn "process_date: invalid wake window for ds=$ds"
    return 1
  fi

  if ! entries=$(apply_wake_window "$entries" "$y_epoch" "$t_epoch"); then
    rm -f "$meta_tmp"
    log_warn "process_date: failed to apply wake window for ds=$ds"
    return 1
  fi
  rm -f "$meta_tmp"

  minutes=$(printf '%s\n' "$entries" | jq '[ .[] | select(.stage != "Awake") | .durationMin ] | add // empty')
  printf '%s\n' "$minutes"
  return 0
}

###############################################################################
# Load entries for target_date & compute totals
###############################################################################

stage_block=$(tmpfile)
meta_block=$(tmpfile)
split_sleep_file "$input_path" "$stage_block" "$meta_block"

entries_err=$(tmpfile)
if ! entries=$(
  raw_to_entries <"$stage_block" | jq "$jq_add_duration_min_filter" 2>"$entries_err"
); then
  err=$(cat "$entries_err" 2>/dev/null || true)
  rm -f "$entries_err" "$stage_block" "$meta_block"
  log_error "failed to parse $input_path: ${err:-jq parsing error}"
  exit 1
fi
rm -f "$entries_err"

yesterday_wake_raw=${YESTERDAY_WAKE:-}
today_wake_raw=${TODAY_WAKE:-}

if [ -z "${yesterday_wake_raw:-}" ]; then
  yesterday_wake_raw=$(read_wake_metadata_value "$meta_block" "YESTERDAY_WAKE" || true)
fi
if [ -z "${today_wake_raw:-}" ]; then
  today_wake_raw=$(read_wake_metadata_value "$meta_block" "TODAY_WAKE" || true)
fi

if [ -z "${yesterday_wake_raw:-}" ] || [ -z "${today_wake_raw:-}" ]; then
  rm -f "$stage_block" "$meta_block"
  log_error "missing wake timestamps (Y=${yesterday_wake_raw:-unset}, T=${today_wake_raw:-unset})"
  exit 1
fi

yesterday_epoch=$(timestamp_to_epoch "$yesterday_wake_raw" || true)
today_epoch=$(timestamp_to_epoch "$today_wake_raw" || true)
if [ -z "${yesterday_epoch:-}" ] || [ -z "${today_epoch:-}" ] || [ "$today_epoch" -le "$yesterday_epoch" ]; then
  rm -f "$stage_block" "$meta_block"
  log_error "invalid wake window (Y=$yesterday_wake_raw, T=$today_wake_raw)"
  exit 1
fi

if ! entries=$(apply_wake_window "$entries" "$yesterday_epoch" "$today_epoch"); then
  rm -f "$stage_block" "$meta_block"
  log_error "failed to trim entries with wake window"
  exit 1
fi

rm -f "$stage_block" "$meta_block"

total_min=$(
  printf '%s\n' "$entries" | jq '[ .[] | select(.stage != "Awake") | .durationMin ] | add // 0'
)

total_h=$(printf '%s\n' "$total_min" | awk '{printf("%d", $1 / 60)}')
total_m=$(printf '%s %s\n' "$total_min" "$total_h" | awk '{m = $1 - $2 * 60; printf("%.0f", m)}')

stage_lines=$(
  printf '%s\n' "$entries" | jq -r '
    group_by(.stage)
    | map({ stage: .[0].stage, mins: (map(.durationMin) | add) })
    | .[]
    | [ .stage, (.mins | tostring) ]
    | @tsv
  '
)

entries_lines=$(
  printf '%s\n' "$entries" | jq -r '
    .[] | [ .stage, (.durationMin | tostring), .start, .end ] | @tsv
  '
)

###############################################################################
# 7-day running average (up to last 7 days with data, incl. target_date)
###############################################################################

past_totals_file=$(tmpfile)
: >"$past_totals_file"

for offset in 6 5 4 3 2 1 0; do
  day_off=$((0 - offset))
  d=$(dt_date_shift_days "$target_date" "$day_off")
  if t=$(process_date "$d"); then
    if [ -n "${t:-}" ]; then
      printf '%s\n' "$t" >>"$past_totals_file"
    fi
  else
    rm -f "$past_totals_file"
    log_error "failed to compute window total for date: $d"
    exit 1
  fi
done

clean_totals=$(sed '/^$/d' "$past_totals_file" || true)
rm -f "$past_totals_file"
count=$(printf '%s\n' "$clean_totals" | sed '/^$/d' | wc -l | awk '{print $1}')

if [ "$count" -gt 0 ]; then
  bc_err=$(tmpfile)
  if ! sum7=$(printf '%s\n' "$clean_totals" | paste -sd+ - | bc -l 2>"$bc_err"); then
    err=$(cat "$bc_err" 2>/dev/null || true)
    rm -f "$bc_err"
    log_error "failed to compute running average with bc: ${err:-bc error}"
    exit 1
  fi
  rm -f "$bc_err"
  avg_min=$(printf '%s\n' "$sum7" | awk -v c="$count" 'BEGIN{OFMT="%.4f"} {print $1 / c}')
else
  avg_min=0
fi

avg_h=$(printf '%s\n' "$avg_min" | awk '{printf("%d", $1 / 60)}')
avg_m=$(printf '%s %s\n' "$avg_min" "$avg_h" | awk '{m = $1 - $2 * 60; printf("%.0f", m)}')

###############################################################################
# Sleep advice
###############################################################################

total_h_dec=$(printf '%s\n' "$total_min" | awk 'BEGIN{OFMT="%.1f"} {print $1 / 60}')
avg_h_dec=$(printf '%s\n' "$avg_min"   | awk 'BEGIN{OFMT="%.1f"} {print $1 / 60}')

sleep_advice_reason=""
sleep_advice="Your 7-day running average is close to your 8-hour target. No catch-up sleep is needed; stick to your normal wake time."

if [ "$(printf '%s < %s\n' "$total_min" "330" | bc -l)" -eq 1 ]; then
  sleep_advice_reason="last_night_very_short"
  sleep_advice=$(printf '%s\n' \
    "Last night was about ${total_h_dec} hours, which is very short." \
    "When possible, disable alarms and sleep until you naturally wake to catch up.")
elif [ "$(printf '%s < %s\n' "$total_min" "360" | bc -l)" -eq 1 ]; then
  sleep_advice_reason="last_night_short"
  sleep_advice=$(printf '%s\n' \
    "Last night was about ${total_h_dec} hours, which is shorter than you want." \
    "Plan to sleep in for around 2 extra hours on your next suitable morning.")
else
  if [ "$(printf '%s < %s\n' "$avg_min" "360" | bc -l)" -eq 1 ]; then
    sleep_advice_reason="avg_very_low"
    sleep_advice=$(printf '%s\n' \
      "Your 7-day running average is about ${avg_h_dec} hours, which is very low compared to your 8-hour target." \
      "When you can, disable alarms and let yourself sleep as late as your schedule allows.")
  elif [ "$(printf '%s < %s\n' "$avg_min" "402" | bc -l)" -eq 1 ]; then
    sleep_advice_reason="avg_low"
    sleep_advice=$(printf '%s\n' \
      "Your 7-day running average is about ${avg_h_dec} hours, which is low." \
      "Plan to sleep in for about 2 extra hours on your next off day.")
  elif [ "$(printf '%s < %s\n' "$avg_min" "438" | bc -l)" -eq 1 ]; then
    sleep_advice_reason="avg_slightly_low"
    sleep_advice=$(printf '%s\n' \
      "Your 7-day running average is about ${avg_h_dec} hours, a bit under your 8-hour target." \
      "A 1-hour sleep-in is optional if you feel you need it.")
  else
    sleep_advice_reason="avg_ok"
    sleep_advice=$(printf '%s\n' \
      "Your 7-day running average is about ${avg_h_dec} hours, close to your 8-hour target." \
      "No catch-up sleep is needed; stick to your normal wake time.")
  fi
fi

log_debug "sleep_advice_reason=$sleep_advice_reason totalMin=$total_min avgMin=$avg_min"

###############################################################################
# Build markdown
###############################################################################

prev=$(dt_date_shift_days "$target_date" -1)
next=$(dt_date_shift_days "$target_date" 1)

link_line="[[${prev} Sleep Summary|<- ${prev} Sleep Summary]] | [[${next} Sleep Summary|${next} Sleep Summary ->]]"

md=$(cat <<EOF
${link_line}

## Sleep Summary for ${target_date}

Total (excl. Awake): ${total_h}h ${total_m}m (${total_min} min)

7-day running average: ${avg_h}h ${avg_m}m (${avg_min} min)

### Sleep Advice
${sleep_advice}

### By Stage:
EOF
)

while IFS="$(printf '\t')" read -r stage mins; do
  [ -z "$stage" ] && continue
  sh=$(printf '%s\n' "$mins" | awk '{printf("%d", $1 / 60)}')
  sm=$(printf '%s %s\n' "$mins" "$sh" | awk '{m = $1 - $2 * 60; printf("%.0f", m)}')
  md=$(printf '%s\n- %s: %sh %sm (%s min)' "$md" "$stage" "$sh" "$sm" "$mins")
done <<EOF
$stage_lines
EOF

md=$(printf '%s\n---\n\n### Full Entries\n' "$md")
while IFS="$(printf '\t')" read -r stage mins start end; do
  [ -z "$stage" ] && continue
  stage_fmt=$(printf '%-6s' "$stage")
  md=$(printf '%s\n- %s | %s min | %s -> %s' "$md" "$stage_fmt" "$mins" "$start" "$end")
done <<EOF
$entries_lines
EOF

###############################################################################
# Emit/write + declare artifacts
###############################################################################

if [ "$dry_run" -eq 1 ]; then
  printf '%s\n' "$md"
  exit 0
fi

# Ensure parent dir exists (default path should already exist, but be safe)
out_dir=${final_output%/*}
if [ ! -d "$out_dir" ]; then
  log_error "output directory does not exist: $out_dir"
  exit 1
fi

printf '%s\n' "$md" >"$final_output"
log_info "wrote $(basename "$final_output")"

# Declare artifact for wrapper-managed commit, if enabled.
if [ -n "${COMMIT_LIST_FILE:-}" ]; then
  # Ensure absolute path
  case "$final_output" in
    /*) abs_out=$final_output ;;
    *)  abs_out=$(
          d=$(pwd -P) && printf '%s/%s\n' "$d" "$final_output"
        ) || { log_error "failed to absolutize output path: $final_output"; exit 10; }
        ;;
  esac
  printf '%s\n' "$abs_out" >>"$COMMIT_LIST_FILE"
  log_debug "declared artifact: $abs_out"
fi
