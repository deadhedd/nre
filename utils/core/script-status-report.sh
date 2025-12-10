#!/bin/sh
# utils/core/script-status-report.sh — generate a simple status report for script failures
# Author: deadhedd
# License: MIT
set -eu

LOG_ROOT=${LOG_ROOT:-/home/obsidian/logs}
LOG_EXT=${LOG_EXT:-.log}

LC_ALL=C
LANG=C
export LC_ALL LANG

extract_exit_code() {
  log_file=$1
  # Extract the last exit=N found in the log
  sed -n 's/.*exit=\([0-9][0-9]*\).*/\1/p' "$log_file" 2>/dev/null | tail -n 1
}

extract_job_name() {
  log_file=$1

  # Try "== job start ==" format first
  job=$(sed -n 's/.*==[[:space:]]*\([^=]*\)[[:space:]]*start[[:space:]]*==.*/\1/p' \
    "$log_file" 2>/dev/null | head -n 1)

  # Trim whitespace
  job=$(printf '%s' "$job" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  # Fall back to requested_cmd basename
  if [ -z "$job" ]; then
    cmd=$(sed -n 's/.*requested_cmd=\(.*\)/\1/p' "$log_file" 2>/dev/null | head -n 1)
    [ -n "$cmd" ] && job=$(basename "$cmd")
  fi

  [ -n "$job" ] || job="(unknown)"
  printf '%s\n' "$job"
}

logs_tmp=$(mktemp)
trap 'rm -f "$logs_tmp"' EXIT HUP INT TERM

find "$LOG_ROOT" -type f -name "*${LOG_EXT}" -print 2>/dev/null >"$logs_tmp" || true

found_failures=0

while IFS= read -r log; do
  [ -f "$log" ] || continue

  exit_code=$(extract_exit_code "$log")

  # Skip logs without exit info
  [ -n "$exit_code" ] || continue

  # Skip successful runs
  [ "$exit_code" = "0" ] && continue

  job=$(extract_job_name "$log")

  printf 'FAIL: job=%s exit_code=%s log=%s\n' \
    "$job" "$exit_code" "$log"

  found_failures=1

done <"$logs_tmp"

rm -f "$logs_tmp"
trap - EXIT HUP INT TERM

exit "$found_failures"
