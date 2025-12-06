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
COMMIT_PLAN=$(mktemp)
export JOB_WRAP_COMMIT_PLAN="$COMMIT_PLAN"

# Where to put logs (change if you like)
HOME_DIR="${HOME:-/home/obsidian}"
LOG_ROOT="${HOME_DIR}/logs"
LOG_ROLLING_VAULT_ROOT="${LOG_ROLLING_VAULT_ROOT:-${VAULT_PATH:-/home/obsidian/vaults/Main}}"

# Group logs by note cadence; fall back to an "other" bucket for non-periodic jobs
SAFE_JOB_NAME=$(printf '%s' "$JOB_NAME" | tr -c 'A-Za-z0-9._-' '-')
case "$SAFE_JOB_NAME" in
  *daily-note*)
LOGDIR="${LOG_ROOT}/daily-notes"
    ;;
  *weekly-note*)
LOGDIR="${LOG_ROOT}/weekly-notes"
    ;;
  *monthly-note*|*quarterly-note*|*yearly-note*|*periodic-note*)
LOGDIR="${LOG_ROOT}/periodic-notes"
    ;;
  *)
LOGDIR="${LOG_ROOT}/other"
    ;;
esac
TS="$(date -u +%Y%m%dT%H%M%SZ)"
RUNLOG_BASE="${LOGDIR}/${SAFE_JOB_NAME}-${TS}.log"
RUNLOG=$(log__periodic_log_path "$RUNLOG_BASE")
LOGDIR_MAPPED=${RUNLOG%/*}
mkdir -p "$LOGDIR_MAPPED"

LATEST="${LOGDIR_MAPPED}/${SAFE_JOB_NAME}-latest.log"
LOG_FILE="$RUNLOG"
LOG_FILE_MAPPED=1
LOG_JOB_NAME="$SAFE_JOB_NAME"
LOG_RUN_TS="$TS"

log_init "$SAFE_JOB_NAME"

# Header
log_info "== ${SAFE_JOB_NAME} start =="
log_info "utc_start=$TS"
log_info "cwd=$(pwd)"
log_info "user=$(id -un 2>/dev/null || printf unknown)"
log_info "path=${PATH:-}"
log_info "requested_cmd=$ORIGINAL_CMD"
log_info "resolved_cmd=$RESOLVED_CMD"
log_info "argv=$(printf '%s ' "$@")"
log_info "------------------------------"

cleanup_temp_log() {
  [ -f "$1" ] || return 0
  rm -f -- "$1"
}

cleanup_commit_plan() {
  [ -f "$COMMIT_PLAN" ] || return 0
  rm -f -- "$COMMIT_PLAN"
}

perform_commit_if_requested() {
  if [ "${STATUS:-1}" -ne 0 ]; then
    log_info "Skipping commit because job exit status=$STATUS"
    return 0
  fi

  [ -n "${JOB_WRAP_DISABLE_COMMIT:-}" ] && return 0

  if [ ! -x "$COMMIT_HELPER" ]; then
    log_warn "Commit helper not executable: $COMMIT_HELPER"
    return 0
  fi

  commit_work_tree=${JOB_WRAP_DEFAULT_WORK_TREE:-$REPO_ROOT}
  commit_message=${JOB_WRAP_DEFAULT_COMMIT_MESSAGE:-"chore(${JOB_NAME}): auto-commit changes"}
  commit_bare_repo=${COMMIT_BARE_REPO:-}
  commit_paths=""

  if [ -s "$COMMIT_PLAN" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        work_tree=*)
          commit_work_tree=${line#work_tree=}
          ;;
        message=*)
          commit_message=${line#message=}
          ;;
        bare_repo=*)
          commit_bare_repo=${line#bare_repo=}
          ;;
        path=*)
          path_value=${line#path=}
          commit_paths=$(printf '%s\n%s' "$commit_paths" "$path_value")
          ;;
      esac
    done <"$COMMIT_PLAN"
  fi

  if [ -z "$commit_paths" ]; then
    if ! command -v git >/dev/null 2>&1; then
      log_warn "Git not available; skipping default commit"
      return 0
    fi

    if ! git -C "$commit_work_tree" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      log_warn "Commit work tree is not a git repository: $commit_work_tree"
      return 0
    fi

    status_output=$(git -C "$commit_work_tree" status --porcelain 2>/dev/null || true)
    if [ -z "$status_output" ]; then
      log_info "No changes detected for default commit"
      return 0
    fi

    commit_paths="."
  fi

  [ -n "$commit_work_tree" ] || { log_warn "Commit plan missing work_tree"; return 0; }
  [ -n "$commit_message" ] || { log_warn "Commit plan missing message"; return 0; }

  set --
  while IFS= read -r path_line || [ -n "$path_line" ]; do
    [ -n "$path_line" ] || continue
    set -- "$@" "$path_line"
  done <<EOF_COMMIT_PATHS
$commit_paths
EOF_COMMIT_PATHS

  [ "$#" -gt 0 ] || { log_warn "Commit plan provided no paths"; return 0; }

  log_info "Committing changes via job wrapper"

  commit_stdout=$(mktemp)
  commit_stderr=$(mktemp)

  set +e
  if [ -n "$commit_bare_repo" ]; then
    COMMIT_BARE_REPO="$commit_bare_repo" \
      "$COMMIT_HELPER" "$commit_work_tree" "$commit_message" "$@" \
      >"$commit_stdout" 2>"$commit_stderr"
  else
    "$COMMIT_HELPER" "$commit_work_tree" "$commit_message" "$@" \
      >"$commit_stdout" 2>"$commit_stderr"
  fi
  commit_status=$?
  set -e

  while IFS= read -r commit_line || [ -n "$commit_line" ]; do
    log_info "$commit_line"
  done <"$commit_stdout"

  while IFS= read -r commit_err_line || [ -n "$commit_err_line" ]; do
    log_warn "$commit_err_line"
  done <"$commit_stderr"

  cleanup_temp_log "$commit_stdout"
  cleanup_temp_log "$commit_stderr"

  [ "$commit_status" -eq 0 ] || return "$commit_status"
}

# Run and capture status + duration
START_SEC="$(date -u +%s)"
CMD_OUTPUT_FILE=$(mktemp)
trap 'cleanup_temp_log "$CMD_OUTPUT_FILE"; cleanup_commit_plan' EXIT HUP INT TERM
set +e
"$@" >"$CMD_OUTPUT_FILE" 2>&1
STATUS=$?
set -e

while IFS= read -r line || [ -n "$line" ]; do
  log_info "$line"
done <"$CMD_OUTPUT_FILE"

cleanup_temp_log "$CMD_OUTPUT_FILE"
trap - EXIT HUP INT TERM

END_SEC="$(date -u +%s)"
DUR_SEC=$(( END_SEC - START_SEC ))

# Footer
log_info "------------------------------"
log_info "exit=$STATUS"
log_info "utc_end=$(date -u +%Y%m%dT%H%M%SZ)"
log_info "duration_seconds=$DUR_SEC"
log_info "== ${SAFE_JOB_NAME} end =="

# Update latest symlink (best-effort)
ln -sf "$(basename "$RUNLOG")" "$LATEST" 2>/dev/null || true

log_rotate

if log_update_rolling_note; then
  rolling_note_path=$(log__rolling_note_path "$LOG_FILE" 2>/dev/null || printf '')
  if [ -n "$rolling_note_path" ]; then
    log_info "Rolling log updated: $rolling_note_path"

    if [ -n "${JOB_WRAP_COMMIT_PLAN:-}" ]; then
      commit_work_tree=${LOG_ROLLING_VAULT_ROOT:-${VAULT_PATH:-/home/obsidian/vaults/Main}}
      commit_job=$(log__safe_job_name "${LOG_JOB_NAME:-$SAFE_JOB_NAME}")

      if ! grep -q '^work_tree=' "$JOB_WRAP_COMMIT_PLAN"; then
        printf 'work_tree=%s\n' "$commit_work_tree" >>"$JOB_WRAP_COMMIT_PLAN"
      fi

      if ! grep -q '^message=' "$JOB_WRAP_COMMIT_PLAN"; then
        printf 'message=%s\n' "logs: update ${commit_job:-log} rolling note" >>"$JOB_WRAP_COMMIT_PLAN"
      fi

      printf 'path=%s\n' "$rolling_note_path" >>"$JOB_WRAP_COMMIT_PLAN"
    fi
  fi
fi

perform_commit_if_requested

cleanup_commit_plan

exit "$STATUS"
