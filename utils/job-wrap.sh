#!/bin/sh
# job-wrap.sh — minimal cron wrapper with simple logging
# Usage: job-wrap.sh <job_name> <command> [args...]

set -eu

JOB_NAME="${1:-}"; shift || true
[ -n "${JOB_NAME}" ] || { echo "Usage: $0 <job_name> <command> [args...]" >&2; exit 2; }
[ $# -gt 0 ] || { echo "Usage: $0 <job_name> <command> [args...]" >&2; exit 2; }

# Where to put logs (change if you like)
HOME_DIR="${HOME:-/home/obsidian}"
LOG_ROOT="${HOME_DIR}/logs"

# Group logs by note cadence
SAFE_JOB_NAME=$(printf '%s' "$JOB_NAME" | tr -c 'A-Za-z0-9._-' '-')
case "$SAFE_JOB_NAME" in
  *daily-note*)
    LOGDIR="${LOG_ROOT}/daily-notes"
    ;;
  *weekly-note*)
    LOGDIR="${LOG_ROOT}/weekly-notes"
    ;;
  *)
    LOGDIR="${LOG_ROOT}/periodic-notes"
    ;;
esac
mkdir -p "$LOGDIR"

# Timestamped logfile + "latest" symlink
TS="$(date -u +%Y%m%dT%H%M%SZ)"
RUNLOG="${LOGDIR}/${SAFE_JOB_NAME}-${TS}.log"
LATEST="${LOGDIR}/${SAFE_JOB_NAME}-latest.log"

# Header
{
  printf '== %s start ==\n' "$SAFE_JOB_NAME"
  printf 'utc_start=%s\n' "$TS"
  printf 'cwd=%s\n' "$(pwd)"
  printf 'user=%s\n' "$(id -un 2>/dev/null || printf unknown)"
  printf 'path=%s\n' "${PATH:-}"
  printf 'cmd=%s\n' "$(printf '%s ' "$@")"
  printf '------------------------------\n'
} >>"$RUNLOG"

# Run and capture status + duration
START_SEC="$(date -u +%s)"
if "$@" >>"$RUNLOG" 2>&1; then
  STATUS=0
else
  STATUS=$?
fi
END_SEC="$(date -u +%s)"
DUR_SEC=$(( END_SEC - START_SEC ))

# Footer
{
  printf '------------------------------\n'
  printf 'exit=%s\n' "$STATUS"
  printf 'utc_end=%s\n' "$(date -u +%Y%m%dT%H%M%SZ)"
  printf 'duration_seconds=%s\n' "$DUR_SEC"
  printf '== %s end ==\n' "$SAFE_JOB_NAME"
} >>"$RUNLOG"

# Update latest symlink (best-effort)
ln -sf "$(basename "$RUNLOG")" "$LATEST" 2>/dev/null || true

# Optional: keep only the newest N logs per job (default 20)
LOG_KEEP="${LOG_KEEP:-20}"
# List newest->oldest, drop beyond N, delete them
# (ls -t is widely available on BSD/GNU; guard for empty)
OLD_LIST=$(ls -1t "$LOGDIR/${SAFE_JOB_NAME}-"*.log 2>/dev/null | awk -v n="$LOG_KEEP" 'NR>n')
if [ -n "${OLD_LIST:-}" ]; then
  # xargs without -r for portability; guarded by the if
  printf '%s\n' "$OLD_LIST" | xargs rm -f
fi

exit "$STATUS"
