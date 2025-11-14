#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd -P)
utils_dir="$repo_root/utils"
commit_helper="$utils_dir/core/commit.sh"
date_helpers="$utils_dir/core/date-period-helpers.sh"
# shellcheck source=../core/date-period-helpers.sh
. "$date_helpers"

vaultRoot="$HOME/automation/obsidian/vaults/Main"
sleepFolder="$vaultRoot/Sleep Data"
backlogPath="$sleepFolder/backfill-raw.txt"

if [ ! -f "$backlogPath" ]; then
  echo "❌ backlog file not found: $backlogPath" >&2
  exit 1
fi

data=$(curl -fsSL "file://$backlogPath")

parse_entries() {
  jq -R '
    (split("\n") | map(select(length>0))) as $l |
    (length / 4) as $q |
    [range(0;$q)|{stage:$l[.],duration:$l[.+$q],start:$l[.+2*$q],end:$l[.+3*$q]}]
  '
}

entries=$(printf '%s' "$data" | parse_entries)

tmpdir=$(mktemp -d)

printf '%s' "$entries" | jq -c '.[]' | while IFS= read -r obj; do
  stage=$(printf '%s' "$obj" | jq -r '.stage')
  duration=$(printf '%s' "$obj" | jq -r '.duration')
  start=$(printf '%s' "$obj" | jq -r '.start')
  end=$(printf '%s' "$obj" | jq -r '.end')
  ts=$(printf '%s' "$start" | jq -R '
        gsub("\u202F|\u00A0";" ") | gsub("\s+";" ") | gsub("^\s+|\s+$";"") | sub(" at ";" ") | (strptime("%B %e, %Y %I:%M %p")? // strptime("%b %e, %Y %I:%M %p")?) | if . then mktime else empty end')
  if [ -z "$ts" ]; then
    continue
  fi
  key=$(jq -n --argjson t "$ts" '
        ($t|strftime("%Y-%m-%d")) as $d |
        (($d+" 12:00")|strptime("%Y-%m-%d %H:%M")|mktime) as $cut |
        if $t < $cut then $d else ($t + 86400 | strftime("%Y-%m-%d")) end')
  mkdir -p "$tmpdir/$key"
  printf '%s\n' "$stage"   >> "$tmpdir/$key/stages"
  printf '%s\n' "$duration" >> "$tmpdir/$key/durations"
  printf '%s\n' "$start"   >> "$tmpdir/$key/starts"
  printf '%s\n' "$end"     >> "$tmpdir/$key/ends"

done

outputs=""
today=$(get_today)
for offset in 0 1 2 3 4 5 6; do
  day_offset=$((0 - offset))
  day=$(shift_utc_date_by_days "$today" "$day_offset")
  if [ -d "$tmpdir/$day" ]; then
    out="$sleepFolder/$day.txt"
    cat "$tmpdir/$day/stages" "$tmpdir/$day/durations" "$tmpdir/$day/starts" "$tmpdir/$day/ends" > "$out"
    outputs="$outputs\n-$out"
    if [ -x "$commit_helper" ]; then
      "$commit_helper" "$vaultRoot" "sleep raw: $day" "$out"
    else
      printf '⚠️ commit helper not found: %s\n' "$commit_helper" >&2
    fi
  fi

done

echo "✅ Generated the following raw files for the past 7 days:"
printf '%s\n' "$outputs" | sed '/^$/d'
