#!/bin/sh
# utils/core/log-capture.sh — Stream capture helpers (POSIX sh)
# Author: deadhedd
# License: MIT
# shellcheck shell=sh
#
# Wrapper-only:
# - job-wrap sets up the plumbing (FIFO etc).
# - This file provides a reader that timestamps+levels each line and writes to sink.
# - Never writes to stdout.

(return 0 2>/dev/null) || { printf '%s\n' "ERR log-capture.sh must be sourced, not executed" >&2; exit 2; }

if [ "${LOG_CAPTURE_LOADED:-0}" -eq 1 ]; then
  return 0
fi
LOG_CAPTURE_LOADED=1

# Requires: log_fmt__line (log-format.sh) + log_sink_write_line (log-sink.sh)
# Reads from stdin, emits each line as:
#   "<ts> OUT <sanitized-line>"
log_capture_stderr() {
  # Read robustly including last line without newline.
  while IFS= read -r line || [ -n "$line" ]; do
    out=$(log_fmt__line "OUT" "$line")
    log_sink_write_line "$out"
  done
}

# Same as above but with explicit level token (e.g. "ERR", "WARN")
log_capture_stream_as() {
  level=$1
  shift || true
  while IFS= read -r line || [ -n "$line" ]; do
    out=$(log_fmt__line "$level" "$line")
    log_sink_write_line "$out"
  done
}
