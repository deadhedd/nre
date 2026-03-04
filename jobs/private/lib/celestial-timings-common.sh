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

###############################################################################
# Logging (domain helper: diagnostics to stderr; keep stdout for data)
###############################################################################
log_debug() { printf '%s\n' "DEBUG: $*" >&2; }
log_info()  { printf '%s\n' "INFO: $*"  >&2; }
log_warn()  { printf '%s\n' "WARN: $*"  >&2; }
log_error() { printf '%s\n' "ERROR: $*" >&2; }

###############################################################################
# Engine datetime integration (use engine dt_now_epoch instead of a local UTC-now)
###############################################################################
# Prefer wrapper-provided REPO_ROOT for stable path resolution.
if [ -z "${ENGINE_LIB_DIR:-}" ]; then
  if [ -n "${REPO_ROOT:-}" ]; then
    ENGINE_LIB_DIR="$REPO_ROOT/engine/lib"
  else
    ENGINE_LIB_DIR="${SCRIPT_DIR:-.}/../../engine/lib"
  fi
fi

if ! command -v dt_now_epoch >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  if [ -r "$ENGINE_LIB_DIR/datetime.sh" ]; then
    . "$ENGINE_LIB_DIR/datetime.sh"
  fi
fi

now_epoch_s() {
  # Prefer engine helper if present; otherwise fall back to date +%s.
  if command -v dt_now_epoch >/dev/null 2>&1; then
    dt_now_epoch
    return 0
  fi
  date +%s
}

###############################################################################
# Net + formatting helpers
###############################################################################
curl_json() {
  curl -fsS --max-time 10 --retry 2 --retry-delay 0 --retry-max-time 15 \
       -H "User-Agent: pagan-timings/1.2 (+local)" "$1"
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

###############################################################################
# UTC-input parsing (domain boundary: UTC -> epoch)
###############################################################################
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

  log_error "to_epoch_utc: unable to parse '$ds'"
  return 1
}
