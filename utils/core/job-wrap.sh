#!/bin/sh
# job-wrap.sh — minimal cron wrapper with simple logging
# Usage: job-wrap.sh <job_name> <command_or_script> [args...]

set -eu

JOB_NAME="${1:-}"; shift || true
[ -n "${JOB_NAME}" ] || { echo "Usage: $0 <job_name> <command_or_script> [args...]" >&2; exit 2; }
[ $# -gt 0 ] || { echo "Usage: $0 <job_name> <command_or_script> [args...]" >&2; exit 2; }

ORIGINAL_CMD="$1"
shift || true

case "$ORIGINAL_CMD" in
  */*)
    RESOLVED_CMD="$ORIGINAL_CMD"
    ;;
  *)
    SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
    UTILS_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
    REPO_ROOT=$(cd "$UTILS_DIR/.." && pwd)
    RESOLVED_CMD=""
    
    # 1) If JOB_WRAP_SEARCH_PATH is set, honor it (non-recursive, like before)
    if [ -n "${JOB_WRAP_SEARCH_PATH:-}" ]; then
      SEARCH_PATH="$JOB_WRAP_SEARCH_PATH"
      OLD_IFS=${IFS}
      IFS=:
      for dir in $SEARCH_PATH; do
        [ -n "$dir" ] || continue
        CANDIDATE="$dir/$ORIGINAL_CMD"
        if [ -x "$CANDIDATE" ]; then
          RESOLVED_CMD="$CANDIDATE"
          break
        fi
      done
      IFS=$OLD_IFS
    fi

    # 2) If still not found, search the repo recursively
    if [ -z "$RESOLVED_CMD" ]; then
      # -perm -111 = any execute bits set (portable)
      # drop -maxdepth if you ever hit a platform without it
      RESOLVED_CMD=$(find "$REPO_ROOT" -type f -name "$ORIGINAL_CMD" -perm -111 2>/dev/null | head -n 1 || true)
    fi

    # 3) If still not found, try PATH
    if [ -z "$RESOLVED_CMD" ]; then
      if RESOLVED_CMD=$(command -v "$ORIGINAL_CMD" 2>/dev/null); then
        :
      else
        RESOLVED_CMD=""
      fi
    fi

    [ -n "$RESOLVED_CMD" ] || {
      printf 'Error: could not resolve command %s under %s or in PATH\n' "$ORIGINAL_CMD" "$REPO_ROOT" >&2
      exit 127
    }
    ;;
esac

set -- "$RESOLVED_CMD" "$@"

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
  printf 'requested_cmd=%s\n' "$ORIGINAL_CMD"
  printf 'resolved_cmd=%s\n' "$RESOLVED_CMD"
  printf 'argv=%s\n' "$(printf '%s ' "$@")"
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
