#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
commit_helper="$script_dir/commit.sh"

vaultRoot="$HOME/automation/obsidian/vaults/Main"
sleepFolder="$vaultRoot/Sleep Data"

today=$(date +%Y-%m-%d)
inputPath="$sleepFolder/$today.txt"
outputPath="$sleepFolder/$today Sleep Summary.md"

if [ ! -f "$inputPath" ]; then
  echo "❌ No input file for $today" >&2
  exit 1
fi

raw_to_entries() {
  jq -R '
    (split("\n") | map(select(length>0))) as $l |
    (length / 4) as $q |
    [range(0;$q)|{stage:$l[.],duration:$l[.+$q],start:$l[.+2*$q],end:$l[.+3*$q]}]
  '
}

cutoff=$(date -d "$today -1 day 12:00" +%s)

entries=$(raw_to_entries < "$inputPath")

filtered=$(printf '%s' "$entries" | jq --argjson cutoff "$cutoff" '
  def clean:
    gsub("\u202F|\u00A0";" ") | gsub("\s+";" ") | gsub("^\s+|\s+$";"") | sub(" at ";" ");
  def toMinutes($d):
    ($d|split(":")) as $p |
    if ($p|length)==3 then ($p[0]|tonumber)*60 + ($p[1]|tonumber) + ($p[2]|tonumber)/60
    elif ($p|length)==2 then ($p[0]|tonumber) + ($p[1]|tonumber)/60
    elif ($p|length)==1 then ($p[0]|tonumber)/60 else 0 end;
  map(.ts = (clean(.start) | (strptime("%B %e, %Y %I:%M %p")? // strptime("%b %e, %Y %I:%M %p")?) | mktime)) |
  map(select(.ts != null and .ts >= $cutoff)) |
  map(.durationMin = toMinutes(.duration))
')

totalMin=$(printf '%s' "$filtered" | jq '[.[] | select(.stage!="Awake") | .durationMin] | add // 0')

stageLines=$(printf '%s' "$filtered" | jq -r 'group_by(.stage) | map({stage: .[0].stage, mins: (map(.durationMin)|add)}) | .[] | [.stage, (.mins|tostring)] | @tsv')
entriesLines=$(printf '%s' "$filtered" | jq -r '.[] | [ .stage, (.durationMin|tostring), .start, .end ] | @tsv')

totalH=$(printf '%s' "$totalMin" | awk '{printf("%d",$1/60)}')
totalM=$(printf '%s %s' "$totalMin" "$totalH" | awk '{m=$1-$2*60; printf("%.0f",m)}')

process_date() {
  ds="$1"
  file="$sleepFolder/$ds.txt"
  [ -f "$file" ] || return
  cutoff=$(date -d "$ds -1 day 12:00" +%s)
  raw_to_entries < "$file" | jq --argjson cutoff "$cutoff" '
    def clean:
      gsub("\u202F|\u00A0";" ") | gsub("\s+";" ") | gsub("^\s+|\s+$";"") | sub(" at ";" ");
    def toMinutes($d):
      ($d|split(":")) as $p |
      if ($p|length)==3 then ($p[0]|tonumber)*60 + ($p[1]|tonumber) + ($p[2]|tonumber)/60
      elif ($p|length)==2 then ($p[0]|tonumber) + ($p[1]|tonumber)/60
      elif ($p|length)==1 then ($p[0]|tonumber)/60 else 0 end;
    map(.ts = (clean(.start) | (strptime("%B %e, %Y %I:%M %p")? // strptime("%b %e, %Y %I:%M %p")?) | mktime)) |
    map(select(.ts != null and .ts >= $cutoff and .stage != "Awake") | toMinutes(.duration)) | add // empty
  '
}

pastTotals=""
for offset in 6 5 4 3 2 1 0; do
  d=$(date -d "$today -$offset day" +%Y-%m-%d)
  t=$(process_date "$d" || true)
  if [ -n "$t" ]; then
    pastTotals="$pastTotals\n$t"
  fi
done

sum7=$(printf '%s' "$pastTotals" | sed '/^$/d' | paste -sd+ - | bc -l)
count=$(printf '%s' "$pastTotals" | sed '/^$/d' | wc -l)
if [ "$count" -gt 0 ]; then
  avgMin=$(echo "$sum7 / $count" | bc -l)
else
  avgMin=0
fi

avgH=$(printf '%s' "$avgMin" | awk '{printf("%d",$1/60)}')
avgM=$(printf '%s %s' "$avgMin" "$avgH" | awk '{m=$1-$2*60; printf("%.0f",m)}')

prev=$(date -d "$today -1 day" +%Y-%m-%d)
next=$(date -d "$today +1 day" +%Y-%m-%d)
linkLine="[[${prev} Sleep Summary|← ${prev} Sleep Summary]] | [[${next} Sleep Summary|${next} Sleep Summary →]]"

md="${linkLine}\n\n"
md="${md}## Sleep Summary for ${today}\n\n"
md="${md}🛌 Total (excl. Awake): ${totalH}h ${totalM}m (${totalMin} min)\n\n"
md="${md}📈 7-day running average: ${avgH}h ${avgM}m (${avgMin} min)\n\n"
md="${md}### By Stage:\n"
while IFS="\t" read -r stage mins; do
  [ -z "$stage" ] && continue
  sh=$(printf '%s' "$mins" | awk '{printf("%d",$1/60)}')
  sm=$(printf '%s %s' "$mins" "$sh" | awk '{m=$1-$2*60; printf("%.0f",m)}')
  md="${md}- ${stage}: ${sh}h ${sm}m (${mins} min)\n"
done <<EOF
$stageLines
EOF

md="${md}\n---\n\n### Full Entries\n"
while IFS="\t" read -r stage mins start end; do
  [ -z "$stage" ] && continue
  md="${md}- $(printf '%-6s' "$stage") | ${mins} min | ${start} → ${end}\n"
done <<EOF
$entriesLines
EOF

printf '%s' "$md" > "$outputPath"
echo "✅ Wrote $(basename "$outputPath")"

if [ -x "$commit_helper" ]; then
  "$commit_helper" "$vaultRoot" "sleep summary: $today" "$outputPath"
else
  printf '⚠️ commit helper not found: %s\n' "$commit_helper" >&2
fi
