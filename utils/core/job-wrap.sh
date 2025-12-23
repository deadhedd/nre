#!/bin/sh
# utils/core/job-wrap.sh — cron-safe wrapper with per-job logs + optional auto-commit
# Author: deadhedd
# License: MIT
# shellcheck shell=sh
#
# Paradigm:
# - Leaf scripts must re-exec via this wrapper when JOB_WRAP_ACTIVE!=1.
# - ONLY this wrapper sources utils/core/log.sh (leaf scripts must NOT).
# - Option A routing:
#     * leaf stdout is sacred (passes through untouched)
#     * leaf stderr is captured and written to per-run log file as OUT lines
# - Each run has: <job>-<timestamp>.log and <job>-latest.log
# - Rotation: keep last N logs (default 10), per job, per bucket.
# - Log path mapping MUST match legacy behavior (daily-notes / weekly-notes / long-cycle / other).
#
# Usage:
#   job-wrap.sh <command_or_script> [args...]
#
# Environment knobs:
#   JOB_WRAP_SEARCH_PATH           Colon-separated dirs to search before repo/PATH.
#   JOB_WRAP_JOB_NAME              Override derived job name (used for logging).
#   JOB_WRAP_DEFAULT_WORK_TREE     Override default commit work tree (else VAULT_PATH).
#   JOB_WRAP_DISABLE_COMMIT        If non-empty, skip commit step.
#   JOB_WRAP_DEFAULT_COMMIT_MESSAGE
#                                  Defaults to:
#                                  "job-wrap(<job>): auto-commit (exit=<status>)"
#
# Debug knobs (all opt-in; never stdout):
#   JOB_WRAP_DEBUG=1               Enable wrapper internal debug.
#   JOB_WRAP_DEBUG_FILE=<path>     Write wrapper debug to this file (else stderr).
#   JOB_WRAP_ASCII_ONLY=1|0        Wrapper dbg sanitization (default 1).
#   JOB_WRAP_XTRACE=1              Enable shell xtrace to JOB_WRAP_XTRACE_FILE.
#   JOB_WRAP_XTRACE_FILE=<path>    File for xtrace output (else $LOG_ROOT/debug/...).
#
# Logging knobs (wrapper -> new logger):
#   LOG_ROOT                       Base logs dir (default ${HOME:-/home/obsidian}/logs)
#   LOG_INTERNAL_LEVEL             DEBUG|INFO|WARN|ERR (default INFO)
#   LOG_ASCII_ONLY                 1|0 (default 1)
#   LOG_KEEP_COUNT                 keep last N (default 10)
#   LOG_INTERNAL_DEBUG             1|0 (default 0)
#   LOG_INTERNAL_DEBUG_FILE        path for logger internal debug (optional)

set -eu
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

export JOB_WRAP_ACTIVE=1

# ------------------------------------------------------------------------------
# Wrapper internal debug (never stdout)
# ------------------------------------------------------------------------------
job_wrap__now() { date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || printf 'unknown'; }

job_wrap__dbg() {
  [ "${JOB_WRAP_DEBUG:-0}" -ne 0 ] || return 0

  ts=$(job_wrap__now)
  if [ "${JOB_WRAP_ASCII_ONLY:-1}" -ne 0 ] 2>/dev/null; then
    msg=$(printf '%s' "$*" | LC_ALL=C tr -cd '\11\12\15\40-\176')
  else
    msg=$*
  fi
  line="$ts DBG $msg"

  if [ -n "${JOB_WRAP_DEBUG_FILE:-}" ]; then
    case "$JOB_WRAP_DEBUG_FILE" in
      */*) d=${JOB_WRAP_DEBUG_FILE%/*}; [ -d "$d" ] || mkdir -p "$d" 2>/dev/null || true ;;
    esac
    printf '%s\n' "$line" >>"$JOB_WRAP_DEBUG_FILE" 2>/dev/null || true
  else
    printf '%s\n' "$line" >&2
  fi
}

# ------------------------------------------------------------------------------
# Args
# ------------------------------------------------------------------------------
ORIGINAL_CMD="${1:-}"
if [ -z "$ORIGINAL_CMD" ]; then
  printf 'Usage: %s <command_or_script> [args...]\n' "$0" >&2
  exit 2
fi
shift || true

# ------------------------------------------------------------------------------
# Paths
# ------------------------------------------------------------------------------
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || {
  printf '%s\n' "ERR job-wrap: cannot resolve SCRIPT_DIR" >&2
  exit 2
}
UTILS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." 2>/dev/null && pwd -P) || {
  printf '%s\n' "ERR job-wrap: cannot resolve UTILS_DIR" >&2
  exit 2
}
REPO_ROOT=$(CDPATH= cd -- "$UTILS_DIR/.." 2>/dev/null && pwd -P) || {
  printf '%s\n' "ERR job-wrap: cannot resolve REPO_ROOT" >&2
  exit 2
}

COMMIT_HELPER="${COMMIT_HELPER:-$SCRIPT_DIR/commit.sh}"

job_wrap__dbg "start: pid=$$ ppid=${PPID:-?} uid=$(id -u 2>/dev/null || printf '?') user=$(id -un 2>/dev/null || printf unknown)"
job_wrap__dbg "paths: SCRIPT_DIR=$SCRIPT_DIR UTILS_DIR=$UTILS_DIR REPO_ROOT=$REPO_ROOT"
job_wrap__dbg "helpers: COMMIT_HELPER=$COMMIT_HELPER"
job_wrap__dbg "cmd: ORIGINAL_CMD=$ORIGINAL_CMD argv=$(printf '%s ' "$@")"
job_wrap__dbg "env: PATH=${PATH:-} HOME=${HOME:-} SHELL=${SHELL:-} VAULT_PATH=${VAULT_PATH:-<unset>} LOG_ROOT=${LOG_ROOT:-<unset>}"

# ------------------------------------------------------------------------------
# Source new logging façade (wrapper-only)
# ------------------------------------------------------------------------------
# shellcheck source=/dev/null
. "$SCRIPT_DIR/log.sh"

# ------------------------------------------------------------------------------
# Optional: enable xtrace to a file (never stdout)
# ------------------------------------------------------------------------------
job_wrap__enable_xtrace() {
  [ "${JOB_WRAP_XTRACE:-0}" -ne 0 ] || return 0

  if [ -z "${JOB_WRAP_XTRACE_FILE:-}" ]; then
    if [ -n "${LOG_ROOT:-}" ]; then
      JOB_WRAP_XTRACE_FILE="$LOG_ROOT/debug/job-wrap.${ORIGINAL_CMD}.$$.xtrace.log"
    else
      JOB_WRAP_XTRACE_FILE="/tmp/job-wrap.${ORIGINAL_CMD}.$$.xtrace.log"
    fi
    export JOB_WRAP_XTRACE_FILE
  fi

  case "$JOB_WRAP_XTRACE_FILE" in
    */*) d=${JOB_WRAP_XTRACE_FILE%/*}; [ -d "$d" ] || mkdir -p "$d" 2>/dev/null || true ;;
  esac

  exec 9>>"$JOB_WRAP_XTRACE_FILE" 2>/dev/null || true
  export PS4='+ ${0##*/}:${LINENO}: '
  set -x
  job_wrap__dbg "xtrace enabled: JOB_WRAP_XTRACE_FILE=$JOB_WRAP_XTRACE_FILE"
}
job_wrap__enable_xtrace || true

# ------------------------------------------------------------------------------
# Resolve the command (legacy behavior preserved)
# ------------------------------------------------------------------------------
RESOLVED_CMD=""

case "$ORIGINAL_CMD" in
  */*)
    RESOLVED_CMD="$ORIGINAL_CMD"
    job_wrap__dbg "resolve: explicit path -> $RESOLVED_CMD"
    ;;
  *)
    if [ -n "${JOB_WRAP_SEARCH_PATH:-}" ]; then
      job_wrap__dbg "resolve: searching JOB_WRAP_SEARCH_PATH=$JOB_WRAP_SEARCH_PATH"
      OLD_IFS=$IFS
      IFS=:
      for dir in $JOB_WRAP_SEARCH_PATH; do
        [ -n "$dir" ] || continue
        CANDIDATE="$dir/$ORIGINAL_CMD"
        job_wrap__dbg "resolve: candidate=$CANDIDATE"
        if [ -x "$CANDIDATE" ]; then
          RESOLVED_CMD=$CANDIDATE
          job_wrap__dbg "resolve: found in search path -> $RESOLVED_CMD"
          break
        fi
      done
      IFS=$OLD_IFS
    fi

    if [ -z "$RESOLVED_CMD" ]; then
      job_wrap__dbg "resolve: searching repo recursively under $REPO_ROOT"
      RESOLVED_CMD=$(
        find "$REPO_ROOT" -type f -name "$ORIGINAL_CMD" -perm -111 2>/dev/null \
          | head -n 1 || true
      )
      [ -n "$RESOLVED_CMD" ] && job_wrap__dbg "resolve: found in repo -> $RESOLVED_CMD"
    fi

    if [ -z "$RESOLVED_CMD" ]; then
      job_wrap__dbg "resolve: searching PATH via command -v"
      if RESOLVED_CMD=$(command -v "$ORIGINAL_CMD" 2>/dev/null); then
        job_wrap__dbg "resolve: found in PATH -> $RESOLVED_CMD"
      else
        RESOLVED_CMD=""
      fi
    fi

    if [ -z "$RESOLVED_CMD" ]; then
      job_wrap__dbg "resolve: FAILED ORIGINAL_CMD=$ORIGINAL_CMD"
      printf 'Error: could not resolve command %s under %s or in PATH\n' \
        "$ORIGINAL_CMD" "$REPO_ROOT" >&2
      exit 127
    fi
    ;;
esac

set -- "$RESOLVED_CMD" "$@"

JOB_BASENAME=$(basename -- "$RESOLVED_CMD")
JOB_NAME="${JOB_WRAP_JOB_NAME:-${JOB_BASENAME%.*}}"

job_wrap__dbg "job: RESOLVED_CMD=$RESOLVED_CMD JOB_BASENAME=$JOB_BASENAME JOB_NAME=$JOB_NAME"

# ------------------------------------------------------------------------------
# Legacy log path mapping (same as old logger)
# ------------------------------------------------------------------------------
job_wrap__default_log_dir() {
  # Mirrors legacy log__default_log_dir mapping.
  case "$1" in
    *daily-note*)   printf '%s' "${LOG_ROOT:-${HOME:-/home/obsidian}/logs}/daily-notes" ;;
    *weekly-note*)  printf '%s' "${LOG_ROOT:-${HOME:-/home/obsidian}/logs}/weekly-notes" ;;
    *monthly-note*|*quarterly-note*|*yearly-note*|*periodic-note*)
                   printf '%s' "${LOG_ROOT:-${HOME:-/home/obsidian}/logs}/long-cycle" ;;
    *)              printf '%s' "${LOG_ROOT:-${HOME:-/home/obsidian}/logs}/other" ;;
  esac
}

job_wrap__runid() { date '+%Y%m%dT%H%M%S' 2>/dev/null || printf 'run'; }

# Set env for new logger
LOG_RUN_TS=${LOG_RUN_TS:-$(job_wrap__runid)}
SAFE_JOB_NAME=$(printf '%s' "$JOB_NAME" | tr -c 'A-Za-z0-9._-' '-')
LOG_DIR=$(job_wrap__default_log_dir "$SAFE_JOB_NAME")
LOG_FILE="$LOG_DIR/$SAFE_JOB_NAME-$LOG_RUN_TS.log"

export JOB_NAME="$SAFE_JOB_NAME"
export LOG_FILE
: "${LOG_KEEP_COUNT:=10}"
: "${LOG_INTERNAL_LEVEL:=INFO}"
: "${LOG_ASCII_ONLY:=1}"
export LOG_KEEP_COUNT LOG_INTERNAL_LEVEL LOG_ASCII_ONLY

# Initialize sink + prune + latest (writes banner)
log_init

# Metadata (replacement for old log_run_job meta lines)
log_audit "== ${JOB_NAME} start =="
log_audit "start=$LOG_RUN_TS"
log_audit "cwd=$(pwd 2>/dev/null || pwd)"
log_audit "user=$(id -un 2>/dev/null || printf unknown)"
log_audit "path=${PATH:-}"
log_audit "requested_cmd=$ORIGINAL_CMD"
log_audit "resolved_cmd=$RESOLVED_CMD"
log_audit "argv=$(printf '%s ' "$@")"
log_audit "log_file=$LOG_FILE"
log_audit "------------------------------"

STATUS=0
JOB_WRAP_SIG=""
JOB_WRAP_SHUTDOWN_DONE=0

# ------------------------------------------------------------------------------
# Commit helper glue (preserve old semantics)
# ------------------------------------------------------------------------------
job_wrap__default_work_tree() {
  if [ -n "${JOB_WRAP_DEFAULT_WORK_TREE:-}" ]; then
    printf '%s\n' "$JOB_WRAP_DEFAULT_WORK_TREE"
    return 0
  fi
  printf '%s\n' "${VAULT_PATH:-/home/obsidian/vaults/Main}"
}

DEFAULT_COMMIT_WORK_TREE=$(job_wrap__default_work_tree)
job_wrap__dbg "commit: DEFAULT_COMMIT_WORK_TREE=$DEFAULT_COMMIT_WORK_TREE"

perform_commit() {
  if [ -n "${JOB_WRAP_DISABLE_COMMIT:-}" ]; then
    job_wrap__dbg "commit: disabled via JOB_WRAP_DISABLE_COMMIT"
    return 0
  fi

  if [ ! -x "$COMMIT_HELPER" ]; then
    log_err "Commit helper not executable: $COMMIT_HELPER"
    job_wrap__dbg "commit: helper not executable: $COMMIT_HELPER"
    return 1
  fi

  commit_work_tree=${DEFAULT_COMMIT_WORK_TREE:-$REPO_ROOT}
  commit_message=${JOB_WRAP_DEFAULT_COMMIT_MESSAGE:-"job-wrap(${JOB_NAME}): auto-commit (exit=${STATUS:-unknown})"}

  job_wrap__dbg "commit: work_tree=$commit_work_tree"
  job_wrap__dbg "commit: message=$commit_message"

  log_audit "Committing changes via job wrapper"
  log_audit "commit_work_tree=$commit_work_tree"

  set +e
  "$COMMIT_HELPER" "$commit_work_tree" "$commit_message" .
  commit_status=$?
  set -e

  job_wrap__dbg "commit: status=$commit_status"
  return "$commit_status"
}

# ------------------------------------------------------------------------------
# Run the job (Option A routing)
#   - stdout passes through untouched
#   - stderr appended to LOG_FILE
# ------------------------------------------------------------------------------
job_pid=""

job_wrap__shutdown() {
  if [ "${JOB_WRAP_SHUTDOWN_DONE:-0}" -ne 0 ] 2>/dev/null; then
    exit "${STATUS:-0}"
  fi
  trap '' INT TERM HUP
  JOB_WRAP_SHUTDOWN_DONE=1

  log_audit "------------------------------"
  if [ -n "${JOB_WRAP_SIG:-}" ]; then
    log_audit "signal=$JOB_WRAP_SIG"
  fi
  log_audit "exit=${STATUS:-0}"
  log_audit "end=$(job_wrap__runid)"
  log_audit "== ${JOB_NAME} end =="

  commit_status=0
  if [ -n "${JOB_WRAP_SIG:-}" ]; then
    if [ "${JOB_WRAP_COMMIT_ON_SIGNAL:-0}" -ne 0 ] 2>/dev/null; then
      if ! perform_commit; then
        commit_status=$?
        log_err "Commit failed after signal (status=$commit_status)"
        job_wrap__dbg "exit: commit failed status=$commit_status"
      fi
    else
      job_wrap__dbg "commit: skipped due to signal=$JOB_WRAP_SIG"
    fi
  else
    if ! perform_commit; then
      commit_status=$?
      log_err "Commit failed with status $commit_status"
      job_wrap__dbg "exit: commit failed status=$commit_status"
    fi
  fi

  if [ "${STATUS:-0}" -eq 0 ] && [ "${commit_status:-0}" -ne 0 ]; then
    STATUS=$commit_status
  fi

  job_wrap__dbg "exit: STATUS=${STATUS:-0}"
  exit "${STATUS:-0}"
}

job_wrap__on_signal() {
  sig=$1
  JOB_WRAP_SIG=$sig
  export JOB_WRAP_SIG

  case "$sig" in
    INT)  STATUS=130 ;;
    TERM) STATUS=143 ;;
    HUP)  STATUS=129 ;;
    *)    STATUS=128 ;;
  esac

  if [ -n "${job_pid:-}" ]; then
    set +e
    kill -TERM "$job_pid" 2>/dev/null
    sleep 1
    kill -KILL "$job_pid" 2>/dev/null
    wait "$job_pid" 2>/dev/null
    set -e
  fi

  job_wrap__shutdown
}

trap 'job_wrap__on_signal INT' INT
trap 'job_wrap__on_signal TERM' TERM
trap 'job_wrap__on_signal HUP' HUP

# Execute the job (note: preserve old behavior of running the resolved path directly)
set +e
"$@" 2>>"$LOG_FILE" &
job_pid=$!
wait "$job_pid"
STATUS=$?
job_pid=""
set -e

job_wrap__shutdown
