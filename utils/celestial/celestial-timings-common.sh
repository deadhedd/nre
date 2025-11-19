#!/bin/sh
# Shared helpers for pagan timing scripts.

# shellcheck shell=sh

# Guard against multiple sourcing.
if [ "${PAGAN_TIMINGS_COMMON_SOURCED:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi
PAGAN_TIMINGS_COMMON_SOURCED=1

LC_ALL=C
: "${TZ:=America/Los_Angeles}"
: "${LAT:=47.7423}"
: "${LON:=-121.9857}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "❌ missing: $1" >&2
    exit 1
  }
}

curl_json() {
  curl -fsS --max-time 10 --retry 2 --retry-delay 0 --retry-max-time 15 \
       -H "User-Agent: pagan-timings/1.2 (+local)" "$1"
}

now_utc_s() {
  date -u +%s
}

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

to_epoch_utc() {
  ds="$1"
  ds_norm=$(printf "%s\n" "$ds" | awk '
    {
      split($0,a,/[[:space:]]+/);
      split(a[1],d,/-/);
      y=d[1]; m=d[2]; dd=d[3];
      if (length(m)==1)  m="0" m;
      if (length(dd)==1) dd="0" dd;
      printf "%s-%s-%s %s\n", y, m, dd, a[2];
    }')

  if date -u -j -f "%Y-%m-%d %H:%M" "$ds_norm" +%s >/dev/null 2>&1; then
    date -u -j -f "%Y-%m-%d %H:%M" "$ds_norm" +%s
    return 0
  fi

  printf "to_epoch_utc: unable to parse '%s'\n" "$ds" >&2
  return 1
}
