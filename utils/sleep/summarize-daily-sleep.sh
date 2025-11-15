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

###############################################################################
# Paths & helpers
###############################################################################

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
utils_dir=$(CDPATH= cd -- "$script_dir/.." && pwd -P)

commit_helper="$utils_dir/core/commit.sh"
date_helpers="$utils_dir/core/date-period-helpers.sh"

# shellcheck source=../core/date-period-helpers.sh
. "$date_helpers"

vaultRoot="$HOME/automation/obsidian/vaults/Main"
sleepFolder="$vaultRoot/Sleep Data"

# Optional arg: explicit date (YYYY-MM-DD). Default: get_today.
target_date="${1:-$(get_today)}"

inputPath="$sleepFolder/$target_date.txt"
outputPath="$sleepFolder/$target_date Sleep Summary.md"

if [ ! -f "$inputPath" ]; then
  echo "❌ No input file for $target_date" >&2
  exit 1
fi

###############################################################################
# Helpers
###############################################################################

# Convert the raw 4-block text file into JSON entries:
# [
#   { "stage": "Core", "duration": "1:23:45", "start": "...", "end": "..." },
#   ...
# ]
raw_to_entries() {
  jq -R '
    (split("\n") | map(select(length>0))) as $l |
    (length / 4) as $q |
    [ range(0; $q)
      | {
          stage:    $l[.],
          duration: $l[. + $q],
          start:    $l[. + 2*$q],
          end:      $l[. + 3*$q]
        }
    ]
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

  raw_to_entries < "$file" | jq "
    $jq_add_duration_min_filter
    | [ .[] | select(.stage != \"Awake\") | .durationMin ]
    | add // empty
  "
}

###############################################################################
# Load entries for target_date & compute totals
###############################################################################

entries=$(
  raw_to_entries < "$inputPath" | jq "$jq_add_duration_min_filter"
)

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

pastTotals=""
for offset in 6 5 4 3 2 1 0; do
  day_offset=$((0 - offset))
  d=$(shift_utc_date_by_days "$target_date" "$day_offset")

  t=$(process_date "$d" || true)
  if [ -n "${t:-}" ]; then
    pastTotals="${pastTotals}\n$t"
  fi
done

cleanTotals=$(printf '%s\n' "$pastTotals" | sed '/^$/d')
count=$(printf '%s\n' "$cleanTotals" | wc -l | awk '{print $1}')

if [ "$count" -gt 0 ]; then
  sum7=$(printf '%s\n' "$cleanTotals" | paste -sd+ - | bc -l)
  avgMin=$(printf '%s\n' "$sum7" | awk -v c="$count" 'BEGIN{OFMT="%.4f"} {print $1 / c}')
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

md="${linkLine}\n\n"
md="${md}## Sleep Summary for ${target_date}\n\n"
md="${md}🛌 Total (excl. Awake): ${totalH}h ${totalM}m (${totalMin} min)\n\n"
md="${md}📈 7-day running average: ${avgH}h ${avgM}m (${avgMin} min)\n\n"

md="${md}### By Stage:\n"
while IFS="$(printf '\t')" read -r stage mins; do
  [ -z "$stage" ] && continue
  sh=$(printf '%s\n' "$mins" | awk '{printf("%d", $1 / 60)}')
  sm=$(printf '%s %s\n' "$mins" "$sh" | awk '{m = $1 - $2 * 60; printf("%.0f", m)}')
  md="${md}- ${stage}: ${sh}h ${sm}m (${mins} min)\n"
done <<EOF
$stageLines
EOF

md="${md}\n---\n\n### Full Entries\n"
while IFS="$(printf '\t')" read -r stage mins start end; do
  [ -z "$stage" ] && continue
  md="${md}- $(printf '%-6s' "$stage") | ${mins} min | ${start} → ${end}\n"
done <<EOF
$entriesLines
EOF

###############################################################################
# Write file & optional commit
###############################################################################

printf '%s' "$md" > "$outputPath"
echo "✅ Wrote $(basename "$outputPath")"

if [ -x "$commit_helper" ]; then
  "$commit_helper" "$vaultRoot" "sleep summary: $target_date" "$outputPath"
else
  printf '⚠️ commit helper not found: %s\n' "$commit_helper" >&2
fi
