#!/bin/sh
# utils/core/run-with-debug.sh — run a job through job-wrap with heavy debug enabled
# Author: deadhedd
# License: MIT
#
# Usage:
#   run-with-debug.sh <command_or_script> [args...]
#
# Output:
#   Writes debug logs under: ${LOG_ROOT:-$HOME/logs}/debug/
#     - job-wrap.<job>.<ts>.<pid>.debug.log
#     - logger.<job>.<ts>.<pid>.debug.log
#     - (optional) xtrace.<job>.<ts>.<pid>.log
#
# Knobs:
#   DEBUG_XTRACE=1   Enable shell xtrace (may be noisy)

set -eu

cmd=${1:-}
[ -n "$cmd" ] || { printf 'Usage: %s <command_or_script> [args...]\n' "$0" >&2; exit 2; }
shift || true

# Prefer existing LOG_ROOT, else default like log.sh
LOG_ROOT=${LOG_ROOT:-${HOME:-/home/obsidian}/logs}
DEBUG_DIR="$LOG_ROOT/debug"

# Safe-ish filename segment (ASCII-ish)
safe_job=$(printf '%s' "$cmd" | tr -c 'A-Za-z0-9._-' '-')
ts=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || printf 'run')
pid=$$

mkdir -p "$DEBUG_DIR" 2>/dev/null || true

JOB_WRAP_DEBUG_FILE="$DEBUG_DIR/job-wrap.$safe_job.$ts.$pid.debug.log"
LOG_INTERNAL_DEBUG_FILE="$DEBUG_DIR/logger.$safe_job.$ts.$pid.debug.log"

export JOB_WRAP_DEBUG=1
export JOB_WRAP_DEBUG_FILE
export LOG_INTERNAL_DEBUG=1
export LOG_INTERNAL_DEBUG_FILE

# Keep wrapper/logger output off stdout by default (protect note pipelines)
: "${LOG_INFO_STREAM:=stderr}"
: "${LOG_DEBUG_STREAM:=stderr}"
export LOG_INFO_STREAM LOG_DEBUG_STREAM

# Optional xtrace
if [ "${DEBUG_XTRACE:-0}" -ne 0 ]; then
  export JOB_WRAP_XTRACE=1
  export JOB_WRAP_XTRACE_FILE="$DEBUG_DIR/xtrace.$safe_job.$ts.$pid.log"
fi

# Resolve job-wrap relative to this script location
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
JOB_WRAP="$SCRIPT_DIR/job-wrap.sh"

if [ ! -x "$JOB_WRAP" ]; then
  printf 'ERR: job-wrap not executable: %s\n' "$JOB_WRAP" >&2
  exit 1
fi

printf '%s\n' "DBG run-with-debug: job-wrap=$JOB_WRAP" >&2
printf '%s\n' "DBG run-with-debug: job=$cmd" >&2
printf '%s\n' "DBG run-with-debug: wrapper_debug=$JOB_WRAP_DEBUG_FILE" >&2
printf '%s\n' "DBG run-with-debug: logger_debug=$LOG_INTERNAL_DEBUG_FILE" >&2
[ "${DEBUG_XTRACE:-0}" -ne 0 ] && printf '%s\n' "DBG run-with-debug: xtrace=$JOB_WRAP_XTRACE_FILE" >&2 || true

"$JOB_WRAP" "$cmd" "$@"
status=$?

printf '%s\n' "DBG run-with-debug: exit=$status" >&2
exit "$status"
