#!/bin/sh
# utils/sleep/raws-into-summaries.sh — Convert raw sleep data into per-day summaries.
# Author: deadhedd
# License: MIT
set -eu

PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

log_info() { printf 'INFO %s\n' "$*"; }
log_warn() { printf 'WARN %s\n' "$*"; }
log_err()  { printf 'ERR %s\n'  "$*"; }

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
utils_dir=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
commit_helper="$utils_dir/core/commit.sh"

vault_root="${VAULT_PATH:-/home/obsidian/vaults/Main}"
sleep_folder="$vault_root/Sleep Data"
input_path="$sleep_folder/backfill-raw.txt"

jq_program='
  def clean:
    gsub("\u202F|\u00A0";" ")
    | gsub("\\s+";" ")
    | gsub("^\\s+|\\s+$";"");

  def parse_ts:
    clean
    | sub(" at ";" ")
    | (strptime("%B %e, %Y %I:%M %p")? // strptime("%b %e, %Y %I:%M %p")?);

  def to_minutes:
    split(":") as $p
    | if ($p|length)==3 then ($p[0]|tonumber)*60 + ($p[1]|tonumber) + ($p[2]|tonumber)/60
      elif ($p|length)==2 then ($p[0]|tonumber)*60 + ($p[1]|tonumber)
      elif ($p|length)==1 then ($p[0]|tonumber)
      else 0 end;

  def sleep_key($ts):
    ($ts | strftime("%Y-%m-%d")) as $base
    | ($base + " 12:00" | strptime("%Y-%m-%d %H:%M") | mktime) as $cutoff
    | if $ts < $cutoff then $base else (($ts + 86400) | strftime("%Y-%m-%d")) end;

  (. | split("\n") | map(select(length>0))) as $lines
  | ($lines | length) as $len
  | ($len / 4 | floor) as $chunk
  | if ($chunk * 4 != $len) then
      { error: "lines_not_divisible", lines: $len }
    else
      [ range(0; $chunk) | {
          stage: $lines[.],
          durationRaw: $lines[. + $chunk],
          start: $lines[. + 2*$chunk],
          end: $lines[. + 3*$chunk]
        } ]
      | map(.durationMin = (.durationRaw | to_minutes))
      | map(.ts = (.start | parse_ts | if . then mktime else null end))
      | ( [ .[] | select(.ts == null) | .start ] ) as $skipped
      | map(select(.ts != null))
      | map(.date = sleep_key(.ts))
      | sort_by(.date, .ts)
      | group_by(.date)
      | map({
          date: (.[0].date),
          entries: [ .[] | {stage, durationMin, start, end} ],
          totalMin: ([ .[] | select(.stage != "Awake") | .durationMin ] | add // 0),
          byStage: (group_by(.stage) | map({key: .[0].stage, value: (map(.durationMin)|add // 0)}) | from_entries)
        })
      | sort_by(.date) as $sorted
      | [ range(0; $sorted|length) as $i |
          $sorted[$i] as $item |
          ($sorted
            | to_entries
            | map(select(.key >= ($i - 6) and .key <= $i))
            | map(.value.totalMin)
          ) as $windowTotals |
          ($windowTotals | length) as $windowLen |
          ($windowTotals | add // 0) as $windowSum |
          $item + {
            avgMin: (if $windowLen > 0 then $windowSum / $windowLen else 0 end),
            prevDate: (if $i > 0 then $sorted[$i-1].date else null end),
            nextDate: (if $i < ($sorted|length - 1) then $sorted[$i+1].date else null end)
          }
        ]
      | { data: ., skipped: $skipped }
    end
'

if [ ! -f "$input_path" ]; then
  log_err "input file not found: $input_path"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  log_err "jq is required but not found in PATH"
  exit 1
fi

raw_data=$(cat -- "$input_path")

jq_output=$(printf '%s' "$raw_data" | jq -R -s "$jq_program")

error_type=$(printf '%s' "$jq_output" | jq -r '.error // ""')
if [ -n "$error_type" ]; then
  line_count=$(printf '%s' "$jq_output" | jq -r '.lines // 0')
  log_err "raw input line count $line_count is not divisible by 4"
  exit 1
fi

data_count=$(printf '%s' "$jq_output" | jq '.data | length')
if [ "$data_count" -eq 0 ]; then
  log_warn "no summaries generated from $input_path"
  exit 0
fi

skipped_count=$(printf '%s' "$jq_output" | jq '.skipped | length')
if [ "$skipped_count" -gt 0 ]; then
  log_warn "skipped $skipped_count entries with unparseable timestamps"
  printf '%s' "$jq_output" | jq -r '.skipped[]' | while IFS= read -r skipped; do
    [ -n "$skipped" ] && log_warn "  skipped: $skipped"
  done
fi

duration_to_hm() {
  awk -v val="$1" 'BEGIN {
    hours = int(val / 60)
    minutes = val - (hours * 60)
    if (minutes < 0) {
      minutes = 0
    }
    printf("%d %.0f", hours, minutes)
  }'
}

format_decimal() {
  awk -v val="$1" 'BEGIN { printf("%.2f", val) }'
}

mkdir -p -- "$sleep_folder"

printf '%s' "$jq_output" | jq -c '.data[]' | while IFS= read -r item; do
  date_key=$(printf '%s' "$item" | jq -r '.date')
  total_min=$(printf '%s' "$item" | jq -r '.totalMin')
  avg_min=$(printf '%s' "$item" | jq -r '.avgMin')
  prev_date=$(printf '%s' "$item" | jq -r '.prevDate // ""')
  next_date=$(printf '%s' "$item" | jq -r '.nextDate // ""')

  set -- $(duration_to_hm "$total_min")
  total_h=$1
  total_m=$2
  set -- $(duration_to_hm "$avg_min")
  avg_h=$1
  avg_m=$2

  total_min_fmt=$(format_decimal "$total_min")
  avg_min_fmt=$(format_decimal "$avg_min")

  link_line=""
  if [ -n "$prev_date" ]; then
    link_line="[[${prev_date} Sleep Summary|← ${prev_date} Sleep Summary]]"
  fi
  if [ -n "$next_date" ]; then
    next_link="[[${next_date} Sleep Summary|${next_date} Sleep Summary →]]"
    if [ -n "$link_line" ]; then
      link_line="$link_line | $next_link"
    else
      link_line="$next_link"
    fi
  fi

  stage_lines=$(printf '%s' "$item" | jq -r '.byStage | to_entries[]? | [.key, (.value|tostring)] | @tsv')
  entry_lines=$(printf '%s' "$item" | jq -r '.entries[] | [.stage, (.durationMin|tostring), .start, .end] | @tsv')

  output_path="$sleep_folder/$date_key Sleep Summary.md"
  {
    if [ -n "$link_line" ]; then
      printf '%s\n\n' "$link_line"
    fi
    printf '## Sleep Summary for %s\n\n' "$date_key"
    printf '🛌 Total (excl. Awake): %sh %sm (%s min)\n\n' "$total_h" "$total_m" "$total_min_fmt"
    printf '📈 7-day running average: %sh %sm (%s min)\n\n' "$avg_h" "$avg_m" "$avg_min_fmt"
    printf '### By Stage:\n'
    if [ -n "$stage_lines" ]; then
      printf '%s\n' "$stage_lines" | while IFS="\t" read -r stage mins; do
        [ -z "$stage" ] && continue
        set -- $(duration_to_hm "$mins")
        shours=$1
        smins=$2
        mins_fmt=$(format_decimal "$mins")
        printf -- '- %s: %sh %sm (%s min)\n' "$stage" "$shours" "$smins" "$mins_fmt"
      done
    fi
    printf '\n---\n\n### Full Entries\n'
    if [ -n "$entry_lines" ]; then
      printf '%s\n' "$entry_lines" | while IFS="\t" read -r stage mins start end; do
        [ -z "$stage" ] && continue
        mins_fmt=$(format_decimal "$mins")
        printf -- '- %s | %s min | %s → %s\n' "$(printf '%-6s' "$stage")" "$mins_fmt" "$start" "$end"
      done
    fi
  } > "$output_path"

  log_info "wrote $(basename -- "$output_path")"

  if [ -x "$commit_helper" ]; then
    "$commit_helper" "$vault_root" "sleep summary: $date_key" "$output_path" || log_warn "commit helper failed for $output_path"
  else
    log_warn "commit helper not executable: $commit_helper"
  fi

done
