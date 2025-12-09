#!/bin/sh
# Print details about the next equinox or solstice.
set -eu


printf 'INFO %s\n' "Starting pagan seasonal lookup"

print_rows() {
  event_label="$1"
  datetime_label="$2"
  time_until="$3"
  tip_text="$4"

  printf '<tr>\n'
  printf '  <td>%s</td>\n' "$event_label"
  printf '  <td>%s</td>\n' "$datetime_label"
  printf '  <td>%s</td>\n' "$time_until"
  printf '</tr>\n'
  printf '<tr class="season-tip-row">\n'
  printf '  <td colspan="3"><strong>Tip:</strong> %s</td>\n' "$tip_text"
  printf '</tr>\n'
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
UTILS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
# shellcheck source=utils/celestial/celestial-timings-common.sh
. "$SCRIPT_DIR/celestial-timings-common.sh"
# shellcheck source=../core/date-period-helpers.sh
. "$UTILS_DIR/core/date-period-helpers.sh"

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
season_tip_default="${PAGAN_TIMINGS_SEASON_TIP:-_(seasonal guidance TBD)_}"

if [ "${OFFLINE:-0}" = "1" ] && [ -z "$custom_rows" ]; then
  printf 'WARN %s\n' "Offline mode detected and no custom rows provided; exiting" >&2
  print_rows "🌀 Offline" "n/a" "n/a" "$season_tip_default"
  exit 0
fi

# 1) Build canonical rows in a robust, pipe-delimited form:
#    |epoch|YYYY-MM-DD HH:MM|Type|
if [ -n "$custom_rows" ]; then
  printf 'INFO %s\n' "Using seasonal rows from PAGAN_TIMINGS_SEASON_ROWS environment variable"
  raw_rows="$custom_rows"
else
  printf 'INFO %s\n' "Fetching seasonal data from USNO API"
  y=$(date -u +%Y)
  url1="https://aa.usno.navy.mil/api/seasons?year=${y}"
  url2="https://aa.usno.navy.mil/api/seasons?year=$(($y+1))"

  curl_json_hdr() {
    curl -fsS --max-time 10 --retry 2 --retry-delay 0 --retry-max-time 15 \
         -H "Accept: application/json" \
         -H "User-Agent: pagan-timings/1.2 (+local)" "$1"
  }

  if ! j1=$(curl_json_hdr "$url1"); then
    printf 'WARN %s\n' "Failed to fetch data for year $y; continuing with empty dataset" >&2
    j1='{"data":[]}'
  else
    printf 'INFO %s\n' "Fetched data for year $y"
  fi
  if ! j2=$(curl_json_hdr "$url2"); then
    printf 'WARN %s\n' "Failed to fetch data for year $(($y+1)); continuing with empty dataset" >&2
    j2='{"data":[]}'
  else
    printf 'INFO %s\n' "Fetched data for year $(($y+1))"
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
    if ep=$(epoch_for_utc_datetime "$iso" 2>/dev/null); then
      printf '|%s|%s|%s|\n' "$ep" "$iso" "$typ"
    fi
  done
)

rows_count=$(printf '%s\n' "$canon_rows" | awk 'NF>0 {c++} END{print c+0}')
printf 'INFO %s\n' "Evaluating seasonal dataset ($rows_count candidate rows)"
if [ -z "$canon_rows" ]; then
  printf 'WARN %s\n' "No seasonal rows available after filtering" >&2
  print_rows "🌀 Unavailable" "n/a" "n/a" "$season_tip_default"
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
  printf 'WARN %s\n' "No future seasonal turning found in dataset" >&2
  print_rows "🌀 Unavailable" "n/a" "n/a" "$season_tip_default"
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
  printf 'ERR  %s\n' "Failed to parse selected row: $choice" >&2
  print_rows "🌀 Unavailable" "n/a" "n/a" "$season_tip_default"
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
printf 'INFO %s\n' "Next seasonal turning is $next_name at $iso (epoch $epoch)"

pretty=$(format_epoch_local "$epoch" "%b %e, %Y · %I:%M %p %Z")
pretty_clean=$(printf '%s' "$pretty" | sed 's/  */ /g')

print_rows \
  "$(season_icon "$next_name") $next_name" \
  "$pretty_clean" \
  "$(fmt_eta "$left")" \
  "$season_tip_default"
