#!/bin/sh
# job-wrap.sh — minimal cron wrapper with simple logging
# Usage: job-wrap.sh <command_or_script> [args...]

set -eu

export JOB_WRAP_ACTIVE=1

ORIGINAL_CMD="${1:-}"
[ -n "$ORIGINAL_CMD" ] || { printf 'Usage: %s <command_or_script> [args...]\n' "$0" >&2; exit 2; }
shift || true

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
UTILS_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(cd "$UTILS_DIR/.." && pwd)
COMMIT_HELPER="$SCRIPT_DIR/commit.sh"

. "$SCRIPT_DIR/log.sh"

case "$ORIGINAL_CMD" in
  */*)
    RESOLVED_CMD="$ORIGINAL_CMD"
    ;;
  *)
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

JOB_BASENAME=$(basename "$RESOLVED_CMD")
JOB_NAME=${JOB_WRAP_JOB_NAME:-${JOB_BASENAME%.*}}

job_wrap__default_work_tree() {
  if [ -n "${JOB_WRAP_DEFAULT_WORK_TREE:-}" ]; then
    printf '%s\n' "$JOB_WRAP_DEFAULT_WORK_TREE"
    return 0
  fi

  printf '%s\n' "${VAULT_PATH:-/home/obsidian/vaults/Main}"
}

DEFAULT_COMMIT_WORK_TREE=$(job_wrap__default_work_tree)

perform_commit() {
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
  "$COMMIT_HELPER" "$commit_work_tree" "$commit_message" \
    .
  commit_status=$?
  set -e

  return "$commit_status"
}

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
  "$@"; then
  STATUS=$?
fi

commit_status=0
if ! perform_commit; then
  commit_status=$?
  log_err "Commit failed with status $commit_status"
fi

if [ "$STATUS" -eq 0 ] && [ "$commit_status" -ne 0 ]; then
  exit "$commit_status"
fi

exit "$STATUS"
