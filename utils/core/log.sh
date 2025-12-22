#!/bin/sh
# utils/core/log.sh — Wrapper logging façade (POSIX sh)
# Author: deadhedd
# License: MIT
# shellcheck shell=sh
#
# Source ONLY from job-wrap.sh. Never from leaf scripts.
# Never writes to stdout.

(return 0 2>/dev/null) || { printf '%s\n' "ERR log.sh must be sourced, not executed" >&2; exit 2; }

if [ "${LOG_FACADE_LOADED:-0}" -eq 1 ]; then
  return 0
fi
LOG_FACADE_LOADED=1

# Resolve sibling paths without requiring LOG_HELPER_DIR.
log__this_dir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || {
  printf '%s\n' "ERR log.sh: cannot resolve own directory" >&2
  exit 2
}

# shellcheck source=log-format.sh
. "$log__this_dir/log-format.sh"
# shellcheck source=log-sink.sh
. "$log__this_dir/log-sink.sh"
# shellcheck source=log-capture.sh
. "$log__this_dir/log-capture.sh"

log_init() {
  # Initializes sink (fd + latest + prune).
  log_sink_init || return 0

  # Banner line (INFO)
  line=$(log_fmt__line "INFO" "log_init: opened LOG_FILE=$LOG_FILE") \
    || line="- ERR log_fmt__line failed in log_init"
  log_sink_write_line "$line" || log_sink__internal "log_init: sink write failed"
  return 0
}

log__emit() {
  level=$1
  shift
  log_level__should "$level" || return 0
  line=$(log_fmt__line "$level" "$*") || line="- ERR log_fmt__line failed"

  log_sink_write_line "$line" || log_sink__internal "emit: sink write failed level=$level"
  return 0
}

log__emit_force() {
  level=$1
  shift
  line=$(log_fmt__line "$level" "$*") || line="- ERR log_fmt__line failed"

  log_sink_write_line "$line" || log_sink__internal "emit_force: sink write failed level=$level"
  return 0
}

log_audit() { log__emit_force "INFO" "$@"; }

log_debug() { log__emit "DEBUG" "$@"; }
log_info()  { log__emit "INFO"  "$@"; }
log_warn()  { log__emit "WARN"  "$@"; }
log_err()   { log__emit "ERR"   "$@"; }
