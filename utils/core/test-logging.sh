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

# Accept an optional exit code for the simulated job
exit_code=${1:-0}

printf 'Simulating log output for exit_code=%s\n' "$exit_code" >&2
printf 'plain output line (stdout)\n'
printf 'info-like line on stdout\n'
printf 'warn-like line on stderr\n' >&2
printf 'error-like line on stderr\n' >&2

exit "$exit_code"
