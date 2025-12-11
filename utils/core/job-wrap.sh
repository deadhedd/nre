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
#                                  Commit message template. Defaults to:
#                                  "job-wrap(<job>): auto-commit (exit=<status>)"
#
#   LOG_ROOT                       Where raw .log files live (handled by log.sh).
#   LOG_ROLLING_VAULT_ROOT         Root of vault for rolling notes (handled by log.sh).

set -eu

# Mark that we're running under the job wrapper (useful for downstream scripts if needed)
export JOB_WRAP_ACTIVE=1

ORIGINAL_CMD="${1:-}"
if [ -z "$ORIGINAL_CMD" ]; then
  printf 'Usage: %s <command_or_script> [args...]\n' "$0" >&2
  exit 2
fi
shift || true

# ---------------------------------------------------------------------------
# Path setup
# ---------------------------------------------------------------------------

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
UTILS_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(cd "$UTILS_DIR/.." && pwd)

# Allow overriding paths for helper/commit script if needed
LOG_HELPER_PATH="${LOG_HELPER_PATH:-$SCRIPT_DIR/log.sh}"
COMMIT_HELPER="${COMMIT_HELPER:-$SCRIPT_DIR/commit.sh}"

# Shellcheck would complain because LOG_HELPER_PATH is dynamic; it's intentional.
# shellcheck source=/dev/null
. "$LOG_HELPER_PATH"

# ---------------------------------------------------------------------------
# Resolve the command we’re supposed to run
# ---------------------------------------------------------------------------

case "$ORIGINAL_CMD" in
  */*)
    # Caller gave an explicit path
    RESOLVED_CMD="$ORIGINAL_CMD"
    ;;
  *)
    RESOLVED_CMD=""

    # 1) If JOB_WRAP_SEARCH_PATH is set, honor it (non-recursive)
    if [ -n "${JOB_WRAP_SEARCH_PATH:-}" ]; then
      SEARCH_PATH=$JOB_WRAP_SEARCH_PATH
      OLD_IFS=$IFS
      IFS=:
      for dir in $SEARCH_PATH; do
        [ -n "$dir" ] || continue
        CANDIDATE="$dir/$ORIGINAL_CMD"
        if [ -x "$CANDIDATE" ]; then
          RESOLVED_CMD=$CANDIDATE
          break
        fi
      done
      IFS=$OLD_IFS
    fi

    # 2) If still not found, search the repo recursively
    if [ -z "$RESOLVED_CMD" ]; then
      # -perm -111 = any execute bits set (portable)
      RESOLVED_CMD=$(
        find "$REPO_ROOT" -type f -name "$ORIGINAL_CMD" -perm -111 2>/dev/null \
          | head -n 1 || true
      )
    fi

    # 3) If still not found, try PATH
    if [ -z "$RESOLVED_CMD" ]; then
      if RESOLVED_CMD=$(command -v "$ORIGINAL_CMD" 2>/dev/null); then
        :
      else
        RESOLVED_CMD=""
      fi
    fi

    if [ -z "$RESOLVED_CMD" ]; then
      printf 'Error: could not resolve command %s under %s or in PATH\n' \
        "$ORIGINAL_CMD" "$REPO_ROOT" >&2
      exit 127
    fi
    ;;
esac

set -- "$RESOLVED_CMD" "$@"

JOB_BASENAME=$(basename "$RESOLVED_CMD")
JOB_NAME=${JOB_WRAP_JOB_NAME:-${JOB_BASENAME%.*}}

# ---------------------------------------------------------------------------
# Commit helper glue
# ---------------------------------------------------------------------------

job_wrap__default_work_tree() {
  if [ -n "${JOB_WRAP_DEFAULT_WORK_TREE:-}" ]; then
    printf '%s\n' "$JOB_WRAP_DEFAULT_WORK_TREE"
    return 0
  fi

  printf '%s\n' "${VAULT_PATH:-/home/obsidian/vaults/Main}"
}

DEFAULT_COMMIT_WORK_TREE=$(job_wrap__default_work_tree)

perform_commit() {
  # Allow disabling commits entirely
  [ -n "${JOB_WRAP_DISABLE_COMMIT:-}" ] && return 0

  if [ ! -x "$COMMIT_HELPER" ]; then
    log_err "Commit helper not executable: $COMMIT_HELPER"
    return 1
  fi

  commit_work_tree=${DEFAULT_COMMIT_WORK_TREE:-$REPO_ROOT}
  commit_message=${JOB_WRAP_DEFAULT_COMMIT_MESSAGE:-"job-wrap(${JOB_NAME}): auto-commit (exit=${STATUS:-unknown})"}

  log_info "Committing changes via job wrapper"
  log_info "commit_work_tree=$commit_work_tree"

  set +e
  "$COMMIT_HELPER" "$commit_work_tree" "$commit_message" .
  commit_status=$?
  set -e

  return "$commit_status"
}

# ---------------------------------------------------------------------------
# Run the job through the logging helper
# ---------------------------------------------------------------------------

STATUS=0
if ! log_run_job "$JOB_NAME" \
  "cwd=$(pwd)" \
  "user=$(id -un 2>/dev/null || printf unknown)" \
  "path=${PATH:-}" \
  "requested_cmd=$ORIGINAL_CMD" \
  "resolved_cmd=$RESOLVED_CMD" \
  "default_commit_work_tree=$DEFAULT_COMMIT_WORK_TREE" \
  "argv=$(printf '%s ' "$@")" \
  -- \
  "$@"
then
  STATUS=$?
fi

# ---------------------------------------------------------------------------
# Post-job commit & exit logic
# ---------------------------------------------------------------------------

commit_status=0
if ! perform_commit; then
  commit_status=$?
  log_err "Commit failed with status $commit_status"
fi

# If the job itself succeeded but commit failed, propagate commit failure
if [ "$STATUS" -eq 0 ] && [ "$commit_status" -ne 0 ]; then
  exit "$commit_status"
fi

exit "$STATUS"
