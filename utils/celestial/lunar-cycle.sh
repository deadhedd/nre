#!/bin/sh
# Print current moon phase details.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=utils/celestial/celestial-timings-common.sh
. "$SCRIPT_DIR/celestial-timings-common.sh"

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

format_utc_date() {
  epoch="$1"
  if d=$(date -u -r "$epoch" +%Y-%m-%d 2>/dev/null); then
    printf "%s\n" "$d"
    return 0
  fi
  printf "n/a\n"
}

if [ "${OFFLINE:-0}" = "1" ]; then
  echo "Moon: 🌙 **(offline)** (illumination n/a) — next 🌙 **Principal Phase** on n/a (in n/a; ~n/a days)"
  exit 0
fi

d=$(date -u +%Y-%m-%d)
t=$(date -u +%H:%M)
url="https://aa.usno.navy.mil/api/celnav?date=${d}&time=${t}&coords=${LAT},${LON}"

if ! json=$(curl_json "$url"); then
  echo "Moon: 🌙 **(unavailable)** (illumination n/a) — next 🌙 **Principal Phase** on n/a (in n/a; ~n/a days)"
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

next_phase_days() {
  target="$1"
  awk -v f="$frac" -v syn="$SYN" -v target="$target" '
    BEGIN {
      t = target
      while (t <= f + 1e-8) {
        t += 1.0
      }
      printf "%.6f\n", (t - f) * syn
    }'
}

new_days=$(next_phase_days 0.0)
full_days=$(next_phase_days 0.5)

cmp=$(awk -v n="$new_days" -v f="$full_days" 'BEGIN{print (n <= f)?0:1}')
if [ "$cmp" -eq 0 ]; then
  left_days="$new_days"
  nextname="New Moon"
else
  left_days="$full_days"
  nextname="Full Moon"
fi

left_secs=$(awk -v d="$left_days" 'BEGIN{printf "%.0f", d*86400.0}')
target_epoch=$(awk -v now="$now" -v s="$left_secs" 'BEGIN{printf "%.0f", now + s}')
next_date=$(format_utc_date "$target_epoch")

if [ "$left_secs" -gt 0 ]; then
  days_count=$(awk -v s="$left_secs" 'BEGIN{printf "%.1f", s/86400.0}')
else
  days_count="0.0"
fi

printf 'DEBUG phase=[%s]\n' "$phase" >&2
printf 'DEBUG icon=[%s]\n' "$(moon_icon "$phase")" >&2

guidance="$(moon_guidance "$phase")"

# Build the message first, then append tip if available
msg=$(printf "Moon: %s **%s** %s — next %s **%s** on %s (in %s; ~%s days)" \
  "$(moon_icon "$phase")" "$phase" "$illum_str" \
  "$(moon_icon "$nextname")" "$nextname" "$next_date" "$(fmt_eta "$left_secs")" "$days_count")

if [ -n "$guidance" ]; then
  msg="$msg — tip: $guidance"
fi

printf "%s\n" "$msg"
