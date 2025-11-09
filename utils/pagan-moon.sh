#!/bin/sh
# Print current moon phase details.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=utils/pagan-timings-common.sh
. "$SCRIPT_DIR/pagan-timings-common.sh"

need curl
need jq
need bc
need awk
need date

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

# Short, practical guidance for each phase (keep it punchy + actionable)
moon_guidance() {
  case "$1" in
    "New Moon")
      echo "Reset: budget, set 1–3 goals, choose a monthly focus."
      ;;
    "Waxing Crescent")
      echo "Start small: take first reps, schedule the next two actions."
      ;;
    "First Quarter")
      echo "Push through friction: fix blockers, make the hard call."
      ;;
    "Waxing Gibbous")
      echo "Refine: tighten your plan, prep reviews, polish in-progress work."
      ;;
    "Full Moon")
      echo "Mid-month check-in: review, rebalance budget, release dead weight."
      ;;
    "Waning Gibbous")
      echo "Integrate: capture lessons, simplify systems, document what worked."
      ;;
    "Last Quarter")
      echo "Close out: cancel/decline low-ROI tasks, wrap lingering items."
      ;;
    "Waning Crescent")
      echo "Downshift: light maintenance only, prep quietly for next reset."
      ;;
    *)
      echo ""
      ;;
  esac
}

frac_mod() {
  num="$1"; den="$2"
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

if [ "${OFFLINE:-0}" = "1" ]; then
  echo "Moon: 🌙 **(offline)** (illumination n/a) — next 🌙 **Principal Phase** in n/a"
  exit 0
fi

d=$(date -u +%Y-%m-%d)
t=$(date -u +%H:%M)
url="https://aa.usno.navy.mil/api/celnav?date=${d}&time=${t}&coords=${LAT},${LON}"

if ! json=$(curl_json "$url"); then
  echo "Moon: 🌙 **(unavailable)** (illumination n/a) — next 🌙 **Principal Phase** in n/a"
  exit 0
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
    *) illum="" ;;
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

SYN="29.530588"
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

guidance="$(moon_guidance "$phase")"

# Build the message first, then append tip if available
msg=$(printf "Moon: %s **%s** %s — next %s **%s** in %s" \
  "$(moon_icon "$phase")" "$phase" "$illum_str" \
  "$(moon_icon "$nextname")" "$nextname" "$(fmt_eta "$left_secs")")

if [ -n "$guidance" ]; then
  msg="$msg — tip: $guidance"
fi

printf "%s\n" "$msg"
