#!/bin/sh
# Print a Markdown snippet with pagan timings:
# - current Moon phase + % illumination (USNO CelNav) with emoji
# - time until the next Equinox/Solstice (USNO Seasons) with emoji
#
# Deps: curl, jq, bc, awk, date (BSD/GNU ok)
# Usage: LAT=47.7423 LON=-121.9857 ./pagan-timings.sh
# Env:
#   TZ=America/Los_Angeles   # pretty timestamp TZ (default America/Los_Angeles)
#   OFFLINE=1                # skip network calls and show "unavailable"

set -eu
LC_ALL=C
: "${TZ:=America/Los_Angeles}"

LAT="${LAT:-47.7423}"
LON="${LON:--121.9857}"

# ---- tool checks ----
need() { command -v "$1" >/dev/null 2>&1 || { echo "❌ missing: $1" >&2; exit 1; }; }
need curl; need jq; need bc; need awk; need date

curl_json() {
  curl -fsS -L --max-time 10 --retry 2 --retry-delay 0 --retry-max-time 15 \
       -H "User-Agent: pagan-timings/1.2 (+local)" "$1"
}

now_utc_s() { date -u +%s; }

# human readable "in Xd Yh Zm"
fmt_eta() {
  secs="$1"
  if [ "${secs#-}" != "$secs" ]; then secs=0; fi
  d=$((secs/86400)); r=$((secs%86400))
  h=$((r/3600));    r=$((r%3600))
  m=$((r/60))
  if   [ "$d" -gt 0 ]; then printf "%dd %dh %dm" "$d" "$h" "$m"
  elif [ "$h" -gt 0 ]; then printf "%dh %dm"     "$h" "$m"
  else                       printf "%dm"        "$m"
  fi
}

# parse "YYYY-M-D H:MM" (UTC) -> epoch seconds (BSD/GNU safe)
to_epoch_utc() {
  ds="$1"
  # normalize "YYYY-M-D H:MM" → "YYYY-MM-DD H:MM" for BSD strptime
  ds_norm=$(printf "%s\n" "$ds" | awk '
    {
      split($0,a,/[[:space:]]+/);              # a[1]=date, a[2]=time
      split(a[1],d,/-/);                       # d[1]=Y, d[2]=M, d[3]=D
      y=d[1]; m=d[2]; dd=d[3];
      if (length(m)==1)  m="0" m;
      if (length(dd)==1) dd="0" dd;
      printf "%s-%s-%s %s\n", y, m, dd, a[2];
    }')

  if date -u -j -f "%Y-%m-%d %H:%M" "$ds_norm" +%s >/dev/null 2>&1; then
    date -u -j -f "%Y-%m-%d %H:%M" "$ds_norm" +%s
  else
    # GNU fallback (not used on OpenBSD, harmless elsewhere)
    date -u -d "$ds_norm UTC" +%s
  fi
}

# fractional part modulo without bc negative wobble — returns frac in [0,1)
frac_mod() {
  num="$1" den="$2"
  awk -v n="$num" -v d="$den" '
    function floor(x){return (x>=0)?int(x):int(x)-1}
    BEGIN {
      if (d==0) {print 0; exit}
      q = n/d
      f = q - floor(q)
      if (f < 0) f += 1
      printf "%.8f\n", f
    }'
}

# ---- emoji helpers ----
moon_icon() {
  case "$1" in
    "New Moon") echo "🌑" ;;
    "Waxing Crescent") echo "🌒" ;;
    "First Quarter") echo "🌓" ;;
    "Waxing Gibbous") echo "🌔" ;;
    "Full Moon") echo "🌕" ;;
    "Waning Gibbous") echo "🌖" ;;
    "Last Quarter") echo "🌗" ;;
    "Waning Crescent") echo "🌘" ;;
    *) echo "🌙" ;;
  esac
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

# ---- moon phase (USNO Celestial Navigation) ----
moon_info() {
  if [ "${OFFLINE:-0}" = "1" ]; then
    echo "Moon: 🌙 **(offline)** (illumination n/a) — next 🌙 **Principal Phase** in n/a"
    return 0
  fi

  # OpenBSD-safe zero-padded date for the API
  d=$(date -u +%Y-%m-%d)
  t=$(date -u +%H:%M)
  url="https://aa.usno.navy.mil/api/celnav?date=${d}&time=${t}&coords=${LAT},${LON}"

  if ! json=$(curl_json "$url"); then
    echo "Moon: 🌙 **(unavailable)** (illumination n/a) — next 🌙 **Principal Phase** in n/a"
    return 0
  fi

  phase=$(printf '%s' "$json" | jq -r '
    .properties.moon_phase
    // .data.moon_phase
    // .moon_phase
    // "Unknown"')

  illum=$(printf '%s' "$json" | jq -r '
    .properties.moon_illum
    // .data.moon_illum
    // .moon_illum
    // empty')

  if [ -z "${illum:-}" ] || [ "$illum" = "null" ]; then
    illum_str="(illumination n/a)"
  else
    case "$illum" in
      *.*|*[0-9]) ;;
      *) illum="";;
    esac
    if [ -n "$illum" ]; then
      gt1=$(awk -v x="$illum" 'BEGIN{print (x>1)?1:0}')
      if [ "$gt1" -eq 1 ]; then
        illum_str="$(awk -v x="$illum" 'BEGIN{printf("%.0f%%", x)}')"
      else
        illum_str="$(awk -v x="$illum" 'BEGIN{printf("%.0f%%", x*100)}')"
      fi
    else
      illum_str="(illumination n/a)"
    fi
  fi

  SYN="29.530588" # days
  ref=$(to_epoch_utc "2000-01-06 18:14")
  now=$(now_utc_s)
  age_days=$(awk -v n="$now" -v r="$ref" 'BEGIN{printf "%.8f", (n-r)/86400.0}')
  frac=$(frac_mod "$age_days" "$SYN")

  nextf=1
  for q in 0.25 0.5 0.75 1.0; do
    lt=$(awk -v f="$frac" -v q="$q" 'BEGIN{print (f<q)?1:0}')
    if [ "$lt" -eq 1 ]; then nextf="$q"; break; fi
  done

  left_days=$(awk -v nf="$nextf" -v f="$frac" -v syn="$SYN" 'BEGIN{printf "%.6f", (nf-f)*syn}')
  left_secs=$(awk -v d="$left_days" 'BEGIN{printf "%d", d*86400}')

  case "$nextf" in
    0.25) nextname="First Quarter" ;;
    0.5)  nextname="Full Moon" ;;
    0.75) nextname="Last Quarter" ;;
    1.0)  nextname="New Moon" ;;
    *)    nextname="Principal Phase" ;;
  esac

  printf "Moon: %s **%s** %s — next %s **%s** in %s\n" \
    "$(moon_icon "$phase")" "$phase" "$illum_str" \
    "$(moon_icon "$nextname")" "$nextname" "$(fmt_eta "$left_secs")"
}

# ---- next seasonal turning (USNO Seasons) ----
next_season() {
  if [ "${OFFLINE:-0}" = "1" ]; then
    echo "Next seasonal turning: 🌀 **(offline)** in n/a"
    return 0
  fi

  y=$(date -u +%Y)
  url1="https://aa.usno.navy.mil/api/seasons?year=${y}"
  url2="https://aa.usno.navy.mil/api/seasons?year=$(($y+1))"

  # Be explicit about JSON
  curl_json_hdr() {
    curl -fsS -L --max-time 10 --retry 2 --retry-delay 0 --retry-max-time 15 \
         -H "Accept: application/json" \
         -H "User-Agent: pagan-timings/1.2 (+local)" "$1"
  }

  if ! j1=$(curl_json_hdr "$url1"); then j1='{"data":[]}'; fi
  if ! j2=$(curl_json_hdr "$url2"); then j2='{"data":[]}'; fi

  NOW=$(now_utc_s)

  # Build the same rows you inspected: "y m d time|phenom"
  rows=$(
    printf '%s\n%s\n' "$j1" "$j2" |
      jq -r '
        .data[]?
        | {y:.year, m:.month, d:.day, t:(.time // ""), p:(.phenom // .phenomenon // "")}
        | select((.p|test("Equinox|Solstice")) and (.t != ""))
        | "\(.y) \(.m) \(.d) \(.t)|\(.p)"'
  )

  # Choose the nearest future event using BSD/GNU-safe epoch conversion
  choose=$(
    printf '%s\n' "$rows" | awk -v now="$NOW" '
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
      {
        split($0,a,"|"); split(a[1],b," ");
        y=b[1]; m=b[2]; d=b[3]; hm=b[4]; name=a[2];
        ts=to_epoch(y,m,d,hm);
        if (ts>now && (best_ts==0 || ts<best_ts)) {best_ts=ts; best_line=$0}
      }
      END{ if (best_ts==0) print "NONE"; else print best_ts "|" best_line }
    '
  )

  [ "$choose" = "NONE" ] && { echo "Next seasonal turning: 🌀 **(unavailable)**"; return 0; }

  ts_next=${choose%%|*}
  rest=${choose#*|}
  raw="${rest%%|*}"   # "y m d HH:MM"
  phen="${rest#*|}"   # "Equinox"/"Solstice"

  # Parse fields
  set -- $raw
  yv="$1"; mv="$2"; dv="$3"; tv="$4"

  # Expand human name for better emoji mapping
  case "$phen" in
    Equinox)
      if [ "$mv" -eq 3 ]; then next_name="Vernal Equinox"; else next_name="Autumnal Equinox"; fi
      ;;
    Solstice)
      if [ "$mv" -eq 6 ]; then next_name="Summer Solstice"; else next_name="Winter Solstice"; fi
      ;;
    *) next_name="$phen" ;;
  esac

  # Pretty local time (string is UTC; we *display* in $TZ)
  iso_clean=$(printf "%04d-%02d-%02d %s" "$yv" "$mv" "$dv" "$tv")
  left=$((ts_next - NOW))
  if date -j -f "%Y-%m-%d %H:%M" "$iso_clean" "+%b %e, %Y %I:%M %p %Z" >/dev/null 2>&1; then
    pretty=$(date -j -f "%Y-%m-%d %H:%M" "$iso_clean" "+%b %e, %Y %I:%M %p %Z")
  else
    pretty=$(date -d "$iso_clean" "+%b %e, %Y %I:%M %p %Z")
  fi

  printf "Next seasonal turning: %s **%s** in %s  \n(%s)\n" \
    "$(season_icon "$next_name")" "$next_name" "$(fmt_eta "$left")" "$pretty"
}

# ---- output ----
echo "### Pagan Timings"
moon_info
next_season
