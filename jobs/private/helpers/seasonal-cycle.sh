#!/bin/sh
# Print details about the next equinox or solstice.
set -eu

###############################################################################
# Logging (helper responsibility: diagnostics to stderr; stdout reserved for data)
###############################################################################
log_debug() { printf '%s\n' "DEBUG: $*" >&2; }
log_info()  { printf '%s\n' "INFO: $*"  >&2; }
log_warn()  { printf '%s\n' "WARN: $*"  >&2; }
log_error() { printf '%s\n' "ERROR: $*" >&2; }

log_info "Starting pagan seasonal lookup"

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

if [ -z "${REPO_ROOT:-}" ]; then
  log_error "REPO_ROOT not set (expected wrapped invocation)"
  exit 1
fi
case "$REPO_ROOT" in
  /*) : ;;
  *)
    log_error "REPO_ROOT not absolute: $REPO_ROOT"
    exit 1
    ;;
esac

###############################################################################
# Engine datetime (epoch + local formatting helpers)
###############################################################################
# shellcheck source=engine/lib/datetime.sh
. "$REPO_ROOT/engine/lib/datetime.sh"

###############################################################################
# Domain helpers (UTC parsing, curl, fmt_eta, etc.)
###############################################################################
# shellcheck source=jobs/private/lib/celestial-timings-common.sh
. "$SCRIPT_DIR/../lib/celestial-timings-common.sh"

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
  log_warn "Offline mode detected and no custom rows provided; exiting"
  print_rows "🌀 Offline" "n/a" "n/a" "$season_tip_default"
  exit 0
fi

# 1) Build canonical rows in a robust, pipe-delimited form:
#    raw rows format: "YYYY M D HH:MM|Phenomenon"
if [ -n "$custom_rows" ]; then
  log_info "Using seasonal rows from PAGAN_TIMINGS_SEASON_ROWS environment variable"
  raw_rows="$custom_rows"
else
  log_info "Fetching seasonal data from USNO API"
  y=$(date -u +%Y)
  url1="https://aa.usno.navy.mil/api/seasons?year=${y}"
  url2="https://aa.usno.navy.mil/api/seasons?year=$(($y+1))"

  # Bespoke curl variant: seasons endpoint wants explicit Accept header.
  curl_json_hdr() {
    curl -fsS --max-time 10 --retry 2 --retry-delay 0 --retry-max-time 15 \
         -H "Accept: application/json" \
         -H "User-Agent: pagan-timings/1.2 (+local)" "$1"
  }

  if ! j1=$(curl_json_hdr "$url1"); then
    log_warn "Failed to fetch data for year $y; continuing with empty dataset"
    j1='{"data":[]}'
  else
    log_info "Fetched data for year $y"
  fi

  if ! j2=$(curl_json_hdr "$url2"); then
    log_warn "Failed to fetch data for year $(($y+1)); continuing with empty dataset"
    j2='{"data":[]}'
  else
    log_info "Fetched data for year $(($y+1))"
  fi

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
    y_=$1; m_=$2; d_=$3; hm_=$4
    [ -n "${y_:-}" ] && [ -n "${m_:-}" ] && [ -n "${d_:-}" ] && [ -n "${hm_:-}" ] || continue

    iso=$(printf "%04d-%02d-%02d %s" "$y_" "$m_" "$d_" "$hm_")

    # ISO here is UTC (USNO). Convert UTC datetime -> epoch via domain helper.
    if ep=$(to_epoch_utc "$iso" 2>/dev/null); then
      printf '|%s|%s|%s|\n' "$ep" "$iso" "$typ"
    else
      log_warn "Skipping unparseable UTC datetime: $iso"
    fi
  done
)

rows_count=$(printf '%s\n' "$canon_rows" | awk 'NF>0 {c++} END{print c+0}')
log_info "Evaluating seasonal dataset ($rows_count candidate rows)"

if [ -z "$canon_rows" ]; then
  log_warn "No seasonal rows available after filtering"
  print_rows "🌀 Unavailable" "n/a" "n/a" "$season_tip_default"
  exit 0
fi

NOW=$(dt_now_epoch)

# 2) Pick the earliest future row using field-safe pipe splitting.
choice=$(printf '%s\n' "$canon_rows" | awk -F'|' -v now="$NOW" '
  NF>=5 {
    ep=$2
    if (ep>now && (best==0 || ep<best)) { best=ep; line=$0 }
  }
  END { if (best==0) print "NONE"; else print line }
')

if [ "$choice" = "NONE" ] || [ -z "$choice" ]; then
  log_warn "No future seasonal turning found in dataset"
  print_rows "🌀 Unavailable" "n/a" "n/a" "$season_tip_default"
  exit 0
fi

# 3) Parse the winning line safely with IFS='|'
epoch="" iso="" phen=""
# Format: |epoch|YYYY-MM-DD HH:MM|Type|
IFS='|' read -r _ epoch iso phen _ <<EOF_ROW
$choice
EOF_ROW

if [ -z "${epoch:-}" ] || [ -z "${iso:-}" ] || [ -z "${phen:-}" ]; then
  log_error "Failed to parse selected row: $choice"
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
log_info "Next seasonal turning is $next_name at $iso (epoch $epoch)"

# Strict: no fallbacks. datetime lib must format this for the current platform.
pretty_clean=$(dt_epoch_to_local_pretty "$epoch")

print_rows \
  "$(season_icon "$next_name") $next_name" \
  "$pretty_clean" \
  "$(fmt_eta "$left")" \
  "$season_tip_default"
