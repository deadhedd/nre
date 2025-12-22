#!/bin/sh
# utils/core/tests/log-sink-keep0.sh — sanity: LOG_KEEP_COUNT=0 keeps current log
# Author: deadhedd
set -eu
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd -P)
job_wrap="$repo_root/utils/core/job-wrap.sh"
script_path="$script_dir/$(basename -- "$0")"

if [ "${JOB_WRAP_ACTIVE:-0}" != "1" ] && [ -x "$job_wrap" ]; then
  JOB_WRAP_ACTIVE=1 exec /bin/sh "$job_wrap" "$script_path" "$@"
fi

[ -n "${LOG_FILE:-}" ] || { printf '%s\n' "ERR LOG_FILE unset" >&2; exit 1; }
[ -f "$LOG_FILE" ] || { printf '%s\n' "ERR LOG_FILE missing: $LOG_FILE" >&2; exit 1; }

if [ -n "${LOG_LATEST:-}" ] && [ ! -e "$LOG_LATEST" ]; then
  printf '%s\n' "ERR LOG_LATEST missing: $LOG_LATEST" >&2
  exit 1
fi

exit 0
