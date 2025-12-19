#!/bin/sh
# job-wrap.sh — cron-safe wrapper with logging + optional auto-commit
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
#   JOB_WRAP_XTRACE=1              Enable shell xtrace to JOB_WRAP_XTRACE_FILE.
#   JOB_WRAP_XTRACE_FILE=<path>    File for xtrace output (else $LOG_ROOT/debug/...).
#
# Logging knobs passed through to log.sh:
#   LOG_HELPER_PATH, LOG_ROOT, LOG_ROLLING_VAULT_ROOT, LOG_INTERNAL_DEBUG, etc.

set -eu

export JOB_WRAP_ACTIVE=1

# ------------------------------------------------------------------------------
# Wrapper internal debug (never stdout)
# ------------------------------------------------------------------------------

job_wrap__now() {
  if command -v date >/dev/null 2>&1; then
    date '+%Y-%m-%dT%H:%M:%S%z'
  else
    printf 'unknown'
  fi
}

job_wrap__dbg() {
  [ "${JOB_WRAP_DEBUG:-0}" -ne 0 ] || return 0

  ts=$(job_wrap__now 2>/dev/null || printf 'unknown')
  # Keep ASCII-only by default to match your terminals
  if [ "${JOB_WRAP_ASCII_ONLY:-1}" -ne 0 ] 2>/dev/null; then
    msg=$(printf '%s' "$*" | LC_ALL=C tr -cd '\11\12\15\40-\176')
  else
    msg=$*
  fi

  line="$ts DBG $msg"

  if [ -n "${JOB_WRAP_DEBUG_FILE:-}" ]; then
    case "$JOB_WRAP_DEBUG_FILE" in
      */*)
        _d=${JOB_WRAP_DEBUG_FILE%/*}
        [ -d "$_d" ] || mkdir -p "$_d" 2>/dev/null || true
        ;;
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
# Path setup
# ------------------------------------------------------------------------------

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
UTILS_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(cd "$UTILS_DIR/.." && pwd)

# Logger bootstrap (explicit, no guessing in log.sh)

# 1) If LOG_HELPER_PATH is set, trust it
if [ -n "${LOG_HELPER_PATH:-}" ]; then
  LOG_HELPER_DIR=${LOG_HELPER_DIR:-$(cd "$(dirname "$LOG_HELPER_PATH")" && pwd)}
else
  # 2) Otherwise default to wrapper directory
  LOG_HELPER_DIR=${LOG_HELPER_DIR:-$SCRIPT_DIR}
  LOG_HELPER_PATH="$LOG_HELPER_DIR/log.sh"
fi

export LOG_HELPER_DIR LOG_HELPER_PATH
COMMIT_HELPER="${COMMIT_HELPER:-$SCRIPT_DIR/commit.sh}"

job_wrap__dbg "start: pid=$$ ppid=${PPID:-?} uid=$(id -u 2>/dev/null || printf '?') user=$(id -un 2>/dev/null || printf unknown)"
job_wrap__dbg "paths: SCRIPT_DIR=$SCRIPT_DIR UTILS_DIR=$UTILS_DIR REPO_ROOT=$REPO_ROOT"
job_wrap__dbg "helpers: LOG_HELPER_PATH=$LOG_HELPER_PATH COMMIT_HELPER=$COMMIT_HELPER"
job_wrap__dbg "cmd: ORIGINAL_CMD=$ORIGINAL_CMD argv=$(printf '%s ' "$@")"
job_wrap__dbg "env: PATH=${PATH:-} HOME=${HOME:-} SHELL=${SHELL:-} VAULT_PATH=${VAULT_PATH:-<unset>} LOG_ROOT=${LOG_ROOT:-<unset>}"

# Make logs safe for content pipelines by default:
: "${LOG_INFO_STREAM:=stderr}"
: "${LOG_DEBUG_STREAM:=stderr}"
export LOG_INFO_STREAM LOG_DEBUG_STREAM

# shellcheck source=/dev/null
. "$LOG_HELPER_PATH"

# ------------------------------------------------------------------------------
# Optional: enable xtrace to a file (never stdout)
# ------------------------------------------------------------------------------

job_wrap__enable_xtrace() {
  [ "${JOB_WRAP_XTRACE:-0}" -ne 0 ] || return 0

  # Default xtrace file under LOG_ROOT/debug if LOG_ROOT exists, else /tmp
  if [ -z "${JOB_WRAP_XTRACE_FILE:-}" ]; then
    if [ -n "${LOG_ROOT:-}" ]; then
      JOB_WRAP_XTRACE_FILE="$LOG_ROOT/debug/job-wrap.${ORIGINAL_CMD}.$$.xtrace.log"
    else
      JOB_WRAP_XTRACE_FILE="/tmp/job-wrap.${ORIGINAL_CMD}.$$.xtrace.log"
    fi
    export JOB_WRAP_XTRACE_FILE
  fi

  case "$JOB_WRAP_XTRACE_FILE" in
    */*)
      _xtd=${JOB_WRAP_XTRACE_FILE%/*}
      [ -d "$_xtd" ] || mkdir -p "$_xtd" 2>/dev/null || true
      ;;
  esac

  # Route xtrace to FD 9
  exec 9>>"$JOB_WRAP_XTRACE_FILE"
  export PS4='+ ${0##*/}:${LINENO}: '
  # Some shells honor BASH_XTRACEFD; sh generally does not, so we redirect via FD 9:
  # Portable approach: many /bin/sh don't support redirecting xtrace output; OpenBSD ksh does.
  # We'll still enable xtrace; if your shell ignores FD routing, it will go to stderr.
  # (Still not stdout.)
  set -x
  job_wrap__dbg "xtrace enabled: JOB_WRAP_XTRACE_FILE=$JOB_WRAP_XTRACE_FILE"
}

# If JOB_WRAP_DEBUG is on and you want xtrace automatically, you can set JOB_WRAP_XTRACE=1.
job_wrap__enable_xtrace || true

# ------------------------------------------------------------------------------
# Resolve the command we’re supposed to run
# ------------------------------------------------------------------------------

RESOLVED_CMD=""

case "$ORIGINAL_CMD" in
  */*)
    RESOLVED_CMD="$ORIGINAL_CMD"
    job_wrap__dbg "resolve: explicit path -> $RESOLVED_CMD"
    ;;
  *)
    # 1) If JOB_WRAP_SEARCH_PATH is set, honor it (non-recursive)
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

    # 2) If still not found, search the repo recursively
    if [ -z "$RESOLVED_CMD" ]; then
      job_wrap__dbg "resolve: searching repo recursively under $REPO_ROOT"
      RESOLVED_CMD=$(
        find "$REPO_ROOT" -type f -name "$ORIGINAL_CMD" -perm -111 2>/dev/null \
          | head -n 1 || true
      )
      [ -n "$RESOLVED_CMD" ] && job_wrap__dbg "resolve: found in repo -> $RESOLVED_CMD"
    fi

    # 3) If still not found, try PATH
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

JOB_BASENAME=$(basename "$RESOLVED_CMD")
JOB_NAME=${JOB_WRAP_JOB_NAME:-${JOB_BASENAME%.*}}

job_wrap__dbg "job: RESOLVED_CMD=$RESOLVED_CMD JOB_BASENAME=$JOB_BASENAME JOB_NAME=$JOB_NAME"

# ------------------------------------------------------------------------------
# Commit helper glue
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

  log_info "Committing changes via job wrapper"
  log_info "commit_work_tree=$commit_work_tree"

  set +e
  "$COMMIT_HELPER" "$commit_work_tree" "$commit_message" .
  commit_status=$?
  set -e

  job_wrap__dbg "commit: status=$commit_status"
  return "$commit_status"
}

# ------------------------------------------------------------------------------
# Run the job through the logging helper
# ------------------------------------------------------------------------------

job_wrap__dbg "invoke: calling log_run_job job=$JOB_NAME cmd=$(printf '%s ' "$@")"
job_wrap__dbg "invoke: context: cwd=$(pwd) user=$(id -un 2>/dev/null || printf unknown) requested_cmd=$ORIGINAL_CMD resolved_cmd=$RESOLVED_CMD"

set +e
log_run_job "$JOB_NAME" \
  "cwd=$(pwd)" \
  "user=$(id -un 2>/dev/null || printf unknown)" \
  "path=${PATH:-}" \
  "requested_cmd=$ORIGINAL_CMD" \
  "resolved_cmd=$RESOLVED_CMD" \
  "default_commit_work_tree=$DEFAULT_COMMIT_WORK_TREE" \
  "argv=$(printf '%s ' "$@")" \
  -- \
  "$@"
STATUS=$?
set -e

if [ "$STATUS" -ne 0 ]; then
  job_wrap__dbg "invoke: log_run_job FAILED status=$STATUS"
else
  job_wrap__dbg "invoke: log_run_job OK"
fi

# ------------------------------------------------------------------------------
# Post-job commit & exit logic
# ------------------------------------------------------------------------------

commit_status=0
if ! perform_commit; then
  commit_status=$?
  log_err "Commit failed with status $commit_status"
  job_wrap__dbg "exit: commit failed status=$commit_status"
fi

if [ "$STATUS" -eq 0 ] && [ "$commit_status" -ne 0 ]; then
  job_wrap__dbg "exit: propagating commit failure $commit_status"
  exit "$commit_status"
fi

job_wrap__dbg "exit: STATUS=$STATUS"
exit "$STATUS"
