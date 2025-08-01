#!/bin/sh
# POSIX sh reimplementation of backfill_sleep_data.js
set -eu

sleep_folder="${HOME}/automation/obsidian/vaults/Main/Sleep Data"
input_path="${sleep_folder}/backfill-raw.txt"

# Ensure dependencies
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

# Convert duration string (HH:MM:SS or MM:SS) to minutes (float)
to_minutes() {
  echo "$1" | awk -F: '{
    if (NF==3) printf "%.2f", $1*60 + $2 + $3/60;
    else if (NF==2) printf "%.2f", $1 + $2/60;
    else if (NF==1) printf "%.2f", $1/60;
    else print "0";
  }'
}

# Get note date from start time with noon cutoff
note_date() {
  input="$1"
  cleaned=$(printf '%s' "$input" | sed 's/,//g; s/ at / /')
  ts=$(date -d "$cleaned" +%s 2>/dev/null || echo "")
  [ -n "$ts" ] || return 1
  day=$(date -d "@$ts" +%Y-%m-%d)
  noon=$(date -d "$day 12:00" +%s)
  if [ "$ts" -lt "$noon" ]; then
    echo "$day"
  else
    date -d "$day +1 day" +%Y-%m-%d
  fi
}

if [ ! -f "$input_path" ]; then
  echo "missing $input_path" >&2
  exit 1
fi

line_count=$(wc -l < "$input_path" | tr -d ' ')
chunk=$((line_count / 4))
if [ $((chunk*4)) -ne "$line_count" ]; then
  echo "⚠️ $line_count lines isn't divisible by 4." >&2
  exit 1
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
sed -n "1,${chunk}p" "$input_path" > "$TMPDIR/stages"
sed -n "$((chunk+1)),$((2*chunk))p" "$input_path" > "$TMPDIR/durations"
sed -n "$((2*chunk+1)),$((3*chunk))p" "$input_path" > "$TMPDIR/starts"
sed -n "$((3*chunk+1)),$((4*chunk))p" "$input_path" > "$TMPDIR/ends"

paste "$TMPDIR/stages" "$TMPDIR/durations" "$TMPDIR/starts" "$TMPDIR/ends" |
while IFS="$(printf '\t')" read -r stage duration start end; do
  mins=$(to_minutes "$duration")
  d=$(note_date "$start") || continue
  printf '{"date":"%s","stage":"%s","duration":%s,"start":"%s","end":"%s"}\n' \
    "$d" "$stage" "$mins" "$start" "$end"
done > "$TMPDIR/entries.jsonl"

# Group by date and compute totals using jq
jq -s '
  group_by(.date) | sort_by(.[0].date) |
  map({
    date: .[0].date,
    entries: .,
    total: (map(select(.stage != "Awake") | .duration) | add),
    by_stage: (group_by(.stage) | map({stage: .[0].stage, mins: (map(.duration)|add)}))
  }) as $days |
  [range(0; length) as $i |
    $days[$i] as $d |
    {
      date: $d.date,
      entries: $d.entries,
      total: $d.total,
      by_stage: $d.by_stage,
      prev: (if $i>0 then "[[\($days[$i-1].date) Sleep Summary|← \($days[$i-1].date) Sleep Summary]]" else "" end),
      next: (if $i<length-1 then "[[\($days[$i+1].date) Sleep Summary|\($days[$i+1].date) Sleep Summary →]]" else "" end),
      avg: ((if $i<6 then 0 else $i-6 end) as $s | ($days[$s:$i+1] | map(.total) | add / length))
    }
  ]
' "$TMPDIR/entries.jsonl" > "$TMPDIR/days.json"

len=$(jq 'length' "$TMPDIR/days.json")
i=0
while [ "$i" -lt "$len" ]; do
  jq --argjson i "$i" -r '
    .[$i] as $d |
    ($d.prev + (if ($d.prev != "" and $d.next != "") then " | " else "" end) + $d.next) as $links |
    ($d.total/60|floor) as $h |
    ($d.total % 60|round) as $m |
    ($d.avg/60|floor) as $ah |
    ($d.avg % 60|round) as $am |
    $d.by_stage as $bs |
    $d.entries as $es |
    ( ($links | select(. != "")) +
      "\n\n## Sleep Summary for \($d.date)\n\n" +
      "🛌 Total (excl. Awake): \($h)h \($m)m (\($d.total|@text) min)\n\n" +
      "📈 7-day running average: \($ah)h \($am)m (\($d.avg|@text) min)\n\n" +
      "### By Stage:\n" +
      ($bs | map("- \(.stage): \((.mins/60|floor))h \((.mins % 60|round))m (\(.mins|@text) min)\n") | join("")) +
      "\n---\n\n### Full Entries\n" +
      ($es | map("- \(.stage) | \(.duration|@text) min | \(.start) → \(.end)\n") | join(""))
    )
  ' "$TMPDIR/days.json" > "$TMPDIR/out.md"

  date=$(jq --argjson i "$i" -r '.[$i].date' "$TMPDIR/days.json")
  out="$sleep_folder/${date} Sleep Summary.md"
  mkdir -p "$sleep_folder"
  cat "$TMPDIR/out.md" > "$out"
  echo "✅ Wrote: $(basename "$out")"
  i=$((i+1))
done
