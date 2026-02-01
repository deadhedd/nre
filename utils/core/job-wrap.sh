#!/bin/sh
# utils/core/job-wrap.sh — cron-safe wrapper with per-job logs + optional auto-commit
# Author: deadhedd
# License: MIT
# shellcheck shell=sh

set -eu
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

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
    msg=$(printf '%s' "$*")
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

job_wrap__fmt_argv() {
  first=1
  for arg in "$@"; do
    if [ "$first" = 1 ]; then
      printf '%s' "$arg"
      first=0
    else
      printf ' %s' "$arg"
    fi
  done
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
job_wrap__dbg "cmd: ORIGINAL_CMD=$ORIGINAL_CMD argv=$(job_wrap__fmt_argv "$@")"
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

# ------------------------------------------------------------------------------
# Transition bridge (temporary): try new wrapper first, fall back to legacy
# ------------------------------------------------------------------------------
# IMPORTANT FIX:
#   This runs BEFORE we mutate argv with:
#     set -- "$RESOLVED_CMD" "$@"
#   so the new wrapper receives the true original args intended for the leaf.
#
if [ "${JOB_WRAP_PREFER_LEGACY:-0}" -eq 0 ] 2>/dev/null; then
  if [ "${JOB_WRAP_BRIDGE_TRIED:-0}" -ne 1 ] 2>/dev/null; then
    NEW_WRAP_CANDIDATE=${JOB_WRAP_NEW_WRAPPER:-"$REPO_ROOT/engine/wrap.sh"}

    # Avoid accidental self-call; loop guard also protects, but this is cheap.
    if [ "$NEW_WRAP_CANDIDATE" != "$0" ] && [ -x "$NEW_WRAP_CANDIDATE" ]; then
      JOB_WRAP_BRIDGE_TRIED=1
      export JOB_WRAP_BRIDGE_TRIED

      job_wrap__dbg "bridge: trying NEW wrapper: $NEW_WRAP_CANDIDATE"

      set +e
      # Option 2: clear JOB_WRAP_ACTIVE for the subprocess so NEW wrapper doesn't think it's already wrapped
      JOB_WRAP_ACTIVE= /bin/sh "$NEW_WRAP_CANDIDATE" "$ORIGINAL_CMD" "$@"
      bridge_rc=$?
      set -e

      if [ "$bridge_rc" -eq 0 ]; then
        job_wrap__dbg "bridge: NEW wrapper succeeded"
        exit 0
      fi

      job_wrap__dbg "bridge: NEW wrapper failed rc=$bridge_rc, falling back to legacy wrapper"
      # fall through to legacy implementation below
    else
      job_wrap__dbg "bridge: NEW wrapper not executable (or self): $NEW_WRAP_CANDIDATE (skipping)"
    fi
  fi
fi

# From here on, legacy wrapper proceeds as normal
set -- "$RESOLVED_CMD" "$@"

JOB_BASENAME=$(basename -- "$RESOLVED_CMD")
JOB_NAME="${JOB_WRAP_JOB_NAME:-${JOB_BASENAME%.*}}"

job_wrap__dbg "job: RESOLVED_CMD=$RESOLVED_CMD JOB_BASENAME=$JOB_BASENAME JOB_NAME=$JOB_NAME"

# ------------------------------------------------------------------------------
# Legacy log path mapping (same as old logger)
# ------------------------------------------------------------------------------
job_wrap__default_log_dir() {
  case "$1" in
    *daily-note*)   printf '%s' "${LOG_ROOT:-${HOME:-/home/obsidian}/logs}/daily-notes" ;;
    *weekly-note*)  printf '%s' "${LOG_ROOT:-${HOME:-/home/obsidian}/logs}/weekly-notes" ;;
    *monthly-note*|*quarterly-note*|*yearly-note*|*periodic-note*)
                   printf '%s' "${LOG_ROOT:-${HOME:-/home/obsidian}/logs}/long-cycle" ;;
    *)              printf '%s' "${LOG_ROOT:-${HOME:-/home/obsidian}/logs}/other" ;;
  esac
}

job_wrap__runid() { date '+%Y%m%dT%H%M%S' 2>/dev/null || printf 'run'; }

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

JOB_WRAP_ACTIVE=1
export JOB_WRAP_ACTIVE

# Initialize sink + prune + latest (writes banner)
log_init

# Metadata
log_audit "== ${JOB_NAME} start =="
log_audit "start=$LOG_RUN_TS"
log_audit "cwd=$(pwd 2>/dev/null || pwd)"
log_audit "user=$(id -un 2>/dev/null || printf unknown)"
log_audit "path=${PATH:-}"
log_audit "requested_cmd=$ORIGINAL_CMD"
log_audit "resolved_cmd=$RESOLVED_CMD"
log_audit "argv=$(job_wrap__fmt_argv "$@")"
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
# Run the job
# ------------------------------------------------------------------------------
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

  job_wrap__shutdown
}

trap 'job_wrap__on_signal INT' INT
trap 'job_wrap__on_signal TERM' TERM
trap 'job_wrap__on_signal HUP' HUP

# Execute the job:
#   - stdout passes through untouched
#   - stderr appended to LOG_FILE
set +e
"$@" 2>>"$LOG_FILE"
STATUS=$?
set -e

job_wrap__shutdown
