#!/bin/sh
# utils/core/test-logging.sh — manual logger test harness
# Author: deadhedd
# License: MIT
set -eu
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd -P)
JOB_WRAP="$REPO_ROOT/utils/core/job-wrap.sh"
SCRIPT_PATH="$SCRIPT_DIR/$(basename -- "$0")"

if [ "${JOB_WRAP_ACTIVE:-0}" != "1" ] && [ -x "$JOB_WRAP" ]; then
  JOB_WRAP_ACTIVE=1 exec /bin/sh "$JOB_WRAP" "$SCRIPT_PATH" "$@"
fi

# Path to your logging helper
LOG_HELPER_PATH="${LOG_HELPER_PATH:-$REPO_ROOT/utils/core/log.sh}"

if [ ! -f "$LOG_HELPER_PATH" ]; then
  printf 'ERROR: LOG_HELPER_PATH does not point to log.sh: %s\n' "$LOG_HELPER_PATH" >&2
  exit 1
fi

# Optional: override these per run if you want
: "${LOG_ROOT:=${HOME}/logs}"
: "${LOG_ROLLING_VAULT_ROOT:=${VAULT_PATH:-$HOME/vaults/Main}}"

# Turn on debug logging so you can see DEBUG lines too
LOG_DEBUG=1
export LOG_ROOT LOG_ROLLING_VAULT_ROOT LOG_DEBUG

# Source the helper
# shellcheck source=/dev/null
. "$LOG_HELPER_PATH"

# Accept an optional exit code for the simulated job
exit_code=${1:-0}

printf 'Running test log job with exit_code=%s\n' "$exit_code"
printf 'LOG_ROOT=%s\n' "$LOG_ROOT"
printf 'LOG_ROLLING_VAULT_ROOT=%s\n' "$LOG_ROLLING_VAULT_ROOT"
printf '\n'

# Run a test job that emits various log levels and a plain line
log_run_job "test-logging" "exit_code=${exit_code}" -- \
  sh -c '
    printf "plain output line (no level prefix)\n"
    printf "INFO this is an info line\n"
    printf "WARN this is a warning line\n" >&2
    printf "ERR this is an error line\n" >&2
    printf "DEBUG this is a debug line\n"
    exit '"$exit_code"'
  '

status=$?

printf '\n'
printf 'log_run_job returned status: %s\n' "$status"

# LOG_FILE should be set/exported by the helper at this point
if [ -n "${LOG_FILE:-}" ] && [ -f "$LOG_FILE" ]; then
  printf '\n'
  printf 'LOG_FILE=%s\n' "$LOG_FILE"
  printf '----- log file contents -----\n'
  cat "$LOG_FILE"
  printf '-----------------------------\n'
else
  printf 'LOG_FILE is not set or does not exist: %s\n' "${LOG_FILE:-<unset>}" >&2
fi
