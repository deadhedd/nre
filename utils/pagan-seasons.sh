#!/bin/sh
# Print details about the next equinox or solstice.
set -eu

log() {
  [ "${PAGAN_TIMINGS_DEBUG:-0}" != "0" ] || return 0
  printf '[pagan-seasons] %s\n' "$1" >&2
}

log "Starting pagan seasonal lookup"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=utils/pagan-timings-common.sh
. "$SCRIPT_DIR/pagan-timings-common.sh"

need curl
need jq
need awk
need date

# Portable UTC → epoch helper (GNU/BSD date)
date_to_epoch_utc() {
  # Args: "YYYY-MM-DD HH:MM"
  if date --version >/dev/null 2>&1; then
    TZ=UTC date -d "$1 UTC" +%s
  else
    TZ=UTC date -j -f "%Y-%m-%d %H:%M" "$1" +%s
  fi
}

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

# 1) Build canonical rows in a robust, pipe-delimited form:
#    |epoch|YYYY-MM-DD HH:MM|Type|
if [ -n "$custom_rows" ]; then
  log "Using seasonal rows from PAGAN_TIMINGS_SEASON_ROWS environment variable"
  raw_rows="$custom_rows"
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

  # Emit lines like: "YYYY M D HH:MM|Phenomenon"
  raw_rows=$(printf '%s\n%s\n' "$j1" "$j2" |
    jq -r '
      .data[]?
      | {y:.year, m:.month, d:.day, t:(.time // ""), p:(.phenom // .phenomenon // "")}
      | select((.p|test("Equinox|Solstice")) and (.t != ""))
      | "\(.y) \(.m) \(.d) \(.t)|\(.p)"')
fi

# Canonicalize to: |epoch|YYYY-MM-DD HH:MM|Type|
canon_rows=$(
  printf '%s\n' "$raw_rows" | awk 'NF>0' | while IFS='|' read -r datepart typ; do
    # datepart is "Y M D HH:MM" (space-separated)
    # shellcheck disable=SC2086
    set -- $datepart ""
    y=$1; m=$2; d=$3; hm=$4
    [ -n "${y:-}" ] && [ -n "${m:-}" ] && [ -n "${d:-}" ] && [ -n "${hm:-}" ] || continue
    iso=$(printf "%04d-%02d-%02d %s" "$y" "$m" "$d" "$hm")
    if ep=$(date_to_epoch_utc "$iso" 2>/dev/null); then
      printf '|%s|%s|%s|\n' "$ep" "$iso" "$typ"
    fi
  done
)

rows_count=$(printf '%s\n' "$canon_rows" | awk 'NF>0 {c++} END{print c+0}')
log "Evaluating seasonal dataset ($rows_count candidate rows)"
if [ -z "$canon_rows" ]; then
  log "No seasonal rows available after filtering"
  echo "Next seasonal turning: 🌀 **(unavailable)**"
  exit 0
fi

NOW=$(now_utc_s)

# 2) Pick the earliest future row using field-safe pipe splitting.
choice=$(printf '%s\n' "$canon_rows" | awk -F'|' -v now="$NOW" '
  NF>=5 {
    ep=$2
    if (ep>now && (best==0 || ep<best)) { best=ep; line=$0 }
  }
  END { if (best==0) print "NONE"; else print line }
')

if [ "$choice" = "NONE" ] || [ -z "$choice" ]; then
  log "No future seasonal turning found in dataset"
  echo "Next seasonal turning: 🌀 **(unavailable)**"
  exit 0
fi

# 3) Parse the winning line safely with IFS='|'
epoch="" iso="" phen=""
#             1    2     3    4     5
# Format:     |  ep |  iso | type |
# indexes:     ^0   ^1    ^2   ^3   ^4  (leading/trailing empties)
IFS='|' read -r _ epoch iso phen _ <<EOF_ROW
$choice
EOF_ROW

if [ -z "${epoch:-}" ] || [ -z "${iso:-}" ] || [ -z "${phen:-}" ]; then
  log "Failed to parse selected row: $choice"
  echo "Next seasonal turning: 🌀 **(unavailable)**"
  exit 0
fi

# 4) Human naming based on month + phenom
month=$(printf "%s" "$iso" | cut -c6-7 | sed 's/^0*//')
case "$phen" in
  Equinox)
    if [ "$month" -eq 3 ]; then next_name="Vernal Equinox"; else next_name="Autumnal Equinox"; fi
    ;;
  Solstice)
    if [ "$month" -eq 6 ]; then next_name="Summer Solstice"; else next_name="Winter Solstice"; fi
    ;;
  *) next_name="$phen" ;;
esac

left=$((epoch - NOW))
log "Next seasonal turning is $next_name at $iso (epoch $epoch)"

# Pretty timestamp in local TZ if possible (BSD/GNU)
if date -j -f "%Y-%m-%d %H:%M" "$iso" "+%b %e, %Y %I:%M %p %Z" >/dev/null 2>&1; then
  pretty=$(date -j -f "%Y-%m-%d %H:%M" "$iso" "+%b %e, %Y %I:%M %p %Z")
else
  pretty=$(date -d "$iso" "+%b %e, %Y %I:%M %p %Z")
fi

printf "Next seasonal turning: %s **%s** in %s  \n(%s)\n" \
  "$(season_icon "$next_name")" "$next_name" "$(fmt_eta "$left")" "$pretty"
