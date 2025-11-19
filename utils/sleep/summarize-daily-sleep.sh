#!/bin/sh
#
# sleep-summary.sh
#
# Generate a sleep summary markdown file for a given date.
# - Input:  "Sleep Data/YYYY-MM-DD.txt"
# - Output: "Sleep Data/YYYY-MM-DD Sleep Summary.md"
#
# The input file is assumed to contain *all* sleep for that date
# (previous ~24h: overnight + naps), already segmented by iOS.
#
# Format of the .txt file (4 equal blocks of lines):
#   1..q:   stage   (e.g. "Core", "REM", "Awake")
#   q+1..2q: duration (e.g. "1:23:45" or "52:10")
#   2q+1..3q: start timestamp (used for display only)
#   3q+1..4q: end timestamp   (used for display only)
#
# This script:
#   - Sums all non-"Awake" durations for the day
#   - Computes a 7-day running average (using up to the last 7 days with data)
#   - Writes a markdown summary note
#   - Optionally commits the note via core/commit.sh
#

set -eu

log_root=${LOG_DIR:-/home/obsidian/logs}
log_file=${LOG_FILE:-"$log_root/summarize-daily-sleep.log"}

if [ ! -d "$log_root" ]; then
  mkdir -p "$log_root"
fi

log_write() {
  level=$1
  shift
  msg=$*
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  line="$timestamp $level $msg"
  printf '%s\n' "$line" >>"$log_file"
  printf '%s\n' "$line"
}

log_info() {
  log_write INFO "$@"
}

log_warn() {
  log_write WARN "$@"
}

log_err() {
  log_write ERR "$@"
}

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
  nbsp=$(printf '\302\240')
  nnbsp=$(printf '\342\200\257')
  normalized=$(printf '%s' "$ts" \
    | tr -d '\r' \
    | sed -e "s/${nbsp}/ /g" -e "s/${nnbsp}/ /g")
  trimmed=$(printf '%s' "$normalized" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  formats='%Y-%m-%dT%H:%M:%S%z|%Y-%m-%dT%H:%M:%S|%Y-%m-%dT%H:%M|%Y-%m-%d %H:%M:%S %z|%Y-%m-%d %H:%M:%S|%Y-%m-%d %H:%M|%b %d, %Y at %I:%M:%S %p|%b %d, %Y at %I:%M %p|%B %d, %Y at %I:%M:%S %p|%B %d, %Y at %I:%M %p'
  old_ifs=$IFS
  IFS='|'
  for fmt in $formats; do
    [ -z "$fmt" ] && continue
    case $fmt in
      *%z*)
        if epoch=$(TZ=UTC date -u -j -f "$fmt" "$trimmed" '+%s' 2>/dev/null); then
          IFS=$old_ifs
          printf '%s\n' "$epoch"
          return 0
        fi
        ;;
      *)
        if epoch=$(date -j -f "$fmt" "$trimmed" '+%s' 2>/dev/null); then
          IFS=$old_ifs
          printf '%s\n' "$epoch"
          return 0
        fi
        ;;
    esac
  done
  IFS=$old_ifs
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
    start_raw=$(printf '%s\n' "$entry" | jq -r '.start')
    end_raw=$(printf '%s\n' "$entry" | jq -r '.end')
    start_epoch=$(timestamp_to_epoch "$start_raw" || true)
    end_epoch=$(timestamp_to_epoch "$end_raw" || true)
    if [ -z "${start_epoch:-}" ] || [ -z "${end_epoch:-}" ]; then
      trim_error=1
      break
    fi
    [ "$end_epoch" -gt "$start_epoch" ] || continue
    [ "$end_epoch" -le "$window_start" ] && continue
    [ "$start_epoch" -ge "$window_end" ] && continue
    clip_start=$start_epoch
    clip_end=$end_epoch
    if [ "$clip_start" -lt "$window_start" ]; then
      clip_start=$window_start
    fi
    if [ "$clip_end" -gt "$window_end" ]; then
      clip_end=$window_end
    fi
    overlap=$((clip_end - clip_start))
    [ "$overlap" -gt 0 ] || continue
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
    printf '%s\n' "$entries_json"
    return 1
  fi
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

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
utils_dir=$(CDPATH= cd -- "$script_dir/.." && pwd -P)

commit_helper="$utils_dir/core/commit.sh"
date_helpers="$utils_dir/core/date-period-helpers.sh"

# shellcheck source=../core/date-period-helpers.sh
. "$date_helpers"

vaultRoot="${VAULT_PATH:-$HOME/vaults/Main}"
sleepFolder="$vaultRoot/Sleep Data"

# Optional arg: explicit date (YYYY-MM-DD). Default: get_today.
target_date="${1:-$(get_today)}"

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

# Convert the raw 4-block text file into JSON entries:
# [
#   { "stage": "Core", "duration": "1:23:45", "start": "...", "end": "..." },
#   ...
# ]
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

# JQ filter to add .durationMin (minutes) to each entry
jq_add_duration_min_filter='
  def toMinutes($d):
    ($d | split(":")) as $p |
    if   ($p | length) == 3 then ($p[0] | tonumber) * 60 + ($p[1] | tonumber) + ($p[2] | tonumber) / 60
    elif ($p | length) == 2 then ($p[0] | tonumber)      + ($p[1] | tonumber) / 60
    elif ($p | length) == 1 then ($p[0] | tonumber) / 60
    else 0 end;
  map(.durationMin = toMinutes(.duration))
'

# Compute total minutes of non-"Awake" sleep for a given date, if file exists.
# Prints a single number (minutes) or nothing if there is no data.
process_date() {
  ds="$1"
  file="$sleepFolder/$ds.txt"
  [ -f "$file" ] || return

  stage_tmp=$(tmpfile)
  meta_tmp=$(tmpfile)
  split_sleep_file "$file" "$stage_tmp" "$meta_tmp"

  err_file=$(tmpfile)
  if ! entries=$(raw_to_entries < "$stage_tmp" | jq "$jq_add_duration_min_filter" 2>"$err_file"); then
    err=$(cat "$err_file")
    rm -f "$err_file"
    rm -f "$stage_tmp" "$meta_tmp"
    log_warn "failed to process $file: ${err:-jq parsing error}"
    return 1
  fi
  rm -f "$err_file" "$stage_tmp"

  y_meta=$(read_wake_metadata_value "$meta_tmp" "YESTERDAY_WAKE" || true)
  t_meta=$(read_wake_metadata_value "$meta_tmp" "TODAY_WAKE" || true)

  if [ -n "${y_meta:-}" ] && [ -n "${t_meta:-}" ]; then
    y_epoch=$(timestamp_to_epoch "$y_meta" || true)
    t_epoch=$(timestamp_to_epoch "$t_meta" || true)
    if [ -n "${y_epoch:-}" ] && [ -n "${t_epoch:-}" ] && [ "$t_epoch" -gt "$y_epoch" ]; then
      trimmed=$(apply_wake_window "$entries" "$y_epoch" "$t_epoch")
      if [ $? -eq 0 ]; then
        entries=$trimmed
      fi
    fi
  fi

  rm -f "$meta_tmp"

  minutes=$(printf '%s\n' "$entries" | jq '
      [ .[] | select(.stage != "Awake") | .durationMin ]
      | add // empty
    ')
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

yesterday_wake_raw=${YESTERDAY_WAKE:-}
today_wake_raw=${TODAY_WAKE:-}

if [ -z "${yesterday_wake_raw:-}" ]; then
  yesterday_wake_raw=$(read_wake_metadata_value "$meta_block" "YESTERDAY_WAKE" || true)
fi
if [ -z "${today_wake_raw:-}" ]; then
  today_wake_raw=$(read_wake_metadata_value "$meta_block" "TODAY_WAKE" || true)
fi

if [ -n "${yesterday_wake_raw:-}" ] && [ -n "${today_wake_raw:-}" ]; then
  yesterday_epoch=$(timestamp_to_epoch "$yesterday_wake_raw" || true)
  today_epoch=$(timestamp_to_epoch "$today_wake_raw" || true)
  if [ -n "${yesterday_epoch:-}" ] && [ -n "${today_epoch:-}" ] && [ "$today_epoch" -gt "$yesterday_epoch" ]; then
    before_count=$(printf '%s\n' "$entries" | jq 'length')
    trimmed_entries=$(apply_wake_window "$entries" "$yesterday_epoch" "$today_epoch")
    if [ $? -eq 0 ]; then
      entries=$trimmed_entries
      after_count=$(printf '%s\n' "$entries" | jq 'length')
      removed=$((before_count - after_count))
      log_info "applied wake window: ${yesterday_wake_raw} (${yesterday_epoch}) → ${today_wake_raw} (${today_epoch}) | trimmed ${removed} entrie(s)"
    else
      log_warn "failed to trim entries with wake window; processing full dataset"
    fi
  else
    log_warn "invalid wake window (${yesterday_wake_raw:-?} to ${today_wake_raw:-?}); processing full dataset"
  fi
else
  log_info "wake timestamps missing (Y=${yesterday_wake_raw:-unset}, T=${today_wake_raw:-unset}); processing full dataset"
fi

rm -f "$stage_block" "$meta_block"

# Total minutes of sleep excluding "Awake"
totalMin=$(
  printf '%s\n' "$entries" | jq '
    [ .[] | select(.stage != "Awake") | .durationMin ] | add // 0
  '
)

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
# ensure empty file
: >"$pastTotals_file"
for offset in 6 5 4 3 2 1 0; do
  day_offset=$((0 - offset))
  d=$(shift_utc_date_by_days "$target_date" "$day_offset")

  t=$(process_date "$d" || true)
  if [ -n "${t:-}" ]; then
    printf '%s\n' "$t" >>"$pastTotals_file"
  fi
done

cleanTotals=$(sed '/^$/d' "$pastTotals_file")
rm -f "$pastTotals_file"
count=$(printf '%s\n' "$cleanTotals" | wc -l | awk '{print $1}')

if [ "$count" -gt 0 ]; then
  bc_err=$(tmpfile)
  if ! sum7=$(printf '%s\n' "$cleanTotals" | paste -sd+ - | bc -l 2>"$bc_err"); then
    err=$(cat "$bc_err")
    rm -f "$bc_err"
    log_err "failed to compute running average with bc: ${err:-bc error}"
    avgMin=0
  else
    rm -f "$bc_err"
    avgMin=$(printf '%s\n' "$sum7" | awk -v c="$count" 'BEGIN{OFMT="%.4f"} {print $1 / c}')
  fi
else
  avgMin=0
fi

avgH=$(printf '%s\n' "$avgMin" | awk '{printf("%d", $1 / 60)}')
avgM=$(printf '%s %s\n' "$avgMin" "$avgH" | awk '{m = $1 - $2 * 60; printf("%.0f", m)}')

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
# Write file & optional commit
###############################################################################

printf '%s\n' "$md" > "$outputPath"
log_info "wrote $(basename "$outputPath")"

if [ -x "$commit_helper" ]; then
  log_info "running commit helper"
  "$commit_helper" "$vaultRoot" "sleep summary: $target_date" "$outputPath"
else
  log_warn "commit helper not found: $commit_helper"
fi
