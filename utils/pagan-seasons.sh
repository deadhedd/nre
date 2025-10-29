#!/bin/sh
# Print details about the next equinox or solstice.
set -eu

log() {
  printf '[pagan-seasons] %s\n' "$1"
}

log "Starting pagan seasonal lookup"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=utils/pagan-timings-common.sh
. "$SCRIPT_DIR/pagan-timings-common.sh"

need curl
need jq
need awk
need date

season_icon() {
  case "$1" in
    *Vernal*|*Spring*) echo "🌸" ;;
    *Summer*)          echo "☀️" ;;
    *Autumn*|*Fall*)   echo "🍁" ;;
    *Winter*)          echo "❄️" ;;
    *)                 echo "🌀" ;;
  esac
}

custom_rows="${PAGAN_TIMINGS_SEASON_ROWS:-}"

if [ "${OFFLINE:-0}" = "1" ] && [ -z "$custom_rows" ]; then
  log "Offline mode detected and no custom rows provided; exiting"
  echo "Next seasonal turning: 🌀 **(offline)** in n/a"
  exit 0
fi

if [ -n "$custom_rows" ]; then
  log "Using seasonal rows from PAGAN_TIMINGS_SEASON_ROWS environment variable"
  rows="$custom_rows"
else
  log "Fetching seasonal data from USNO API"
  y=$(date -u +%Y)
  url1="https://aa.usno.navy.mil/api/seasons?year=${y}"
  url2="https://aa.usno.navy.mil/api/seasons?year=$(($y+1))"

  curl_json_hdr() {
    curl -fsS --max-time 10 --retry 2 --retry-delay 0 --retry-max-time 15 \
         -H "Accept: application/json" \
         -H "User-Agent: pagan-timings/1.2 (+local)" "$1"
  }

  if ! j1=$(curl_json_hdr "$url1"); then
    log "Failed to fetch data for year $y; continuing with empty dataset"
    j1='{"data":[]}'
  else
    log "Fetched data for year $y"
  fi
  if ! j2=$(curl_json_hdr "$url2"); then
    log "Failed to fetch data for year $(($y+1)); continuing with empty dataset"
    j2='{"data":[]}'
  else
    log "Fetched data for year $(($y+1))"
  fi

  rows=$(printf '%s\n%s\n' "$j1" "$j2" |
    jq -r '
      .data[]?
      | {y:.year, m:.month, d:.day, t:(.time // ""), p:(.phenom // .phenomenon // "")}
      | select((.p|test("Equinox|Solstice")) and (.t != ""))
      | "\(.y) \(.m) \(.d) \(.t)|\(.p)"')
fi

NOW=$(now_utc_s)

rows_list=$(printf '%s\n' "$rows" | awk 'NF>0 {print}')
rows_count=$(printf '%s\n' "$rows_list" | awk 'NF>0 {c++} END{print c+0}')
log "Evaluating seasonal dataset ($rows_count candidate rows)"
if [ -z "$rows_list" ]; then
  log "No seasonal rows available after filtering"
  echo "Next seasonal turning: 🌀 **(unavailable)**"
  exit 0
fi

ts_next=""
raw=""
phen=""

while :; do
  choose=$(printf '%s\n' "$rows_list" | awk -v now="$NOW" '
    function pad2(x){return (x<10)?"0"x:x}
    function to_epoch(y,m,d,hm,  cmd,ep) {
      cmd = "date -u -j -f \"%Y-%m-%d %H:%M\" \"" y "-" pad2(m) "-" pad2(d) " " hm "\" +%s 2>/dev/null"
      cmd | getline ep; close(cmd)
      if (ep == "") {
        cmd = "date -u -d \"" y "-" m "-" d " " hm " UTC\" +%s 2>/dev/null"
        cmd | getline ep; close(cmd)
      }
      return ep
    }
    BEGIN{best_ts=0; best_line=""}
    NF==0 {next}
    {
      split($0,a,"|"); split(a[1],b," ");
      y=b[1]; m=b[2]; d=b[3]; hm=b[4];
      ts=to_epoch(y,m,d,hm);
      if (ts>now && (best_ts==0 || ts<best_ts)) {best_ts=ts; best_line=$0}
    }
    END{ if (best_ts==0) print "NONE"; else print best_ts "|" best_line }
  ')

  if [ "$choose" = "NONE" ] || [ -z "$choose" ]; then
    log "No future seasonal turning found in dataset"
    echo "Next seasonal turning: 🌀 **(unavailable)**"
    exit 0
  fi

  ts_candidate=${choose%%|*}
  rest=${choose#*|}
  raw_candidate="${rest%%|*}"
  phen_candidate="${rest#*|}"

  yv=""; mv=""; dv=""; tv=""
  IFS=' ' read -r yv mv dv tv <<EOF_ROW || true
$raw_candidate
EOF_ROW

  if [ -n "$yv" ] && [ -n "$mv" ] && [ -n "$dv" ] && [ -n "$tv" ]; then
    ts_next="$ts_candidate"
    raw="$raw_candidate"
    phen="$phen_candidate"
    log "Selected seasonal turning: $phen on $raw"
    break
  fi

  log "Skipping malformed row: $raw_candidate|$phen_candidate"
  rows_list=$(printf '%s\n' "$rows_list" | awk -v skip="$rest" '
    BEGIN{skipped=0}
    {
      if (!skipped && $0==skip) {skipped=1; next}
      if (NF>0) print
    }
  ')

  if [ -z "$rows_list" ]; then
    log "Ran out of seasonal rows while searching for valid entry"
    echo "Next seasonal turning: 🌀 **(unavailable)**"
    exit 0
  fi
done

if [ -z "$ts_next" ]; then
  log "Failed to determine timestamp for next seasonal turning"
  echo "Next seasonal turning: 🌀 **(unavailable)**"
  exit 0
fi

case "$phen" in
  Equinox)
    if [ "$mv" -eq 3 ]; then next_name="Vernal Equinox"; else next_name="Autumnal Equinox"; fi
    ;;
  Solstice)
    if [ "$mv" -eq 6 ]; then next_name="Summer Solstice"; else next_name="Winter Solstice"; fi
    ;;
  *) next_name="$phen" ;;
esac

iso_clean=$(printf "%04d-%02d-%02d %s" "$yv" "$mv" "$dv" "$tv")
left=$((ts_next - NOW))
log "Next seasonal turning is $next_name at $iso_clean (epoch $ts_next)"
if date -j -f "%Y-%m-%d %H:%M" "$iso_clean" "+%b %e, %Y %I:%M %p %Z" >/dev/null 2>&1; then
  pretty=$(date -j -f "%Y-%m-%d %H:%M" "$iso_clean" "+%b %e, %Y %I:%M %p %Z")
else
  pretty=$(date -d "$iso_clean" "+%b %e, %Y %I:%M %p %Z")
fi

printf "Next seasonal turning: %s **%s** in %s  \n(%s)\n" \
  "$(season_icon "$next_name")" "$next_name" "$(fmt_eta "$left")" "$pretty"
