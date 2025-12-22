#!/bin/sh
# utils/core/log-sink.sh — File sink + latest link + rotation (POSIX sh)
# Author: deadhedd
# License: MIT
# shellcheck shell=sh
#
# Wrapper-only:
# - Must be sourced by job-wrap.sh (NOT leaf scripts).
# - Never writes to stdout.
#
# Required env (set by job-wrap before log_sink_init):
#   JOB_WRAP_ACTIVE=1
#   JOB_NAME=<safe-ish job name; used for log naming/patterns>
#   LOG_FILE=<absolute timestamped log file path>
#
# Optional env:
#   LOG_LATEST=<path to latest symlink> (default: <dir>/<JOB_NAME>-latest.log)
#   LOG_KEEP_COUNT=<N>                 (default: 10)
#   LOG_TRUNCATE=1|0                   (default: 0; 1 truncates LOG_FILE at init)
#
# Internal debug (diagnose logger itself):
#   LOG_INTERNAL_DEBUG=1
#   LOG_INTERNAL_DEBUG_FILE=<path>     (if unset, falls back to stderr)

(return 0 2>/dev/null) || { printf '%s\n' "ERR log-sink.sh must be sourced, not executed" >&2; exit 2; }

if [ "${LOG_SINK_LOADED:-0}" -eq 1 ]; then
  return 0
fi
LOG_SINK_LOADED=1

: "${LOG_KEEP_COUNT:=10}"
: "${LOG_TRUNCATE:=0}"

log_sink__internal() {
  [ "${LOG_INTERNAL_DEBUG:-0}" = "1" ] || return 0
  msg=$*
  ts=$(date '+%Y-%m-%dT%H:%M:%S%z')
  if [ -n "${LOG_INTERNAL_DEBUG_FILE:-}" ]; then
    {
      printf '%s %s\n' "$ts" "$msg"
    } >>"$LOG_INTERNAL_DEBUG_FILE" 2>/dev/null || printf '%s\n' "WARN log_sink__internal: failed to write LOG_INTERNAL_DEBUG_FILE" >&2
  else
    printf '%s %s\n' "$ts" "$msg" >&2
  fi
}

log_sink__ensure_dir() {
  p=$1
  case "$p" in
    */*)
      d=${p%/*}
      [ -d "$d" ] || mkdir -p -- "$d" 2>/dev/null || return 1
      ;;
  esac
  return 0
}

log_sink__update_latest() {
  log_file=$1
  latest=$2

  [ -n "$latest" ] || return 0
  log_sink__ensure_dir "$latest" || { log_sink__internal "latest: mkdir failed for $latest"; return 0; }

  ln -sf -- "$log_file" "$latest" 2>/dev/null || log_sink__internal "latest: ln -sf failed file=$log_file latest=$latest"
}

log_sink__prune_keep_last_n() {
  log_dir=$1
  job_name=$2
  keep_n=$3

  [ -n "$log_dir" ] || return 0
  [ -n "$job_name" ] || return 0

  case "$keep_n" in
    ''|*[!0-9]*)
      log_sink__internal "prune: skip invalid keep_n=$keep_n"
      return 0
      ;;
  esac

  if [ "$keep_n" -le 0 ]; then
    log_sink__internal "prune: skip non-positive keep_n=$keep_n"
    return 0
  fi

  # Tight glob: <JOB_NAME>-????????T??????.log
  glob="${log_dir%/}/${job_name}-????????T??????.log"

  # Expand glob
  # shellcheck disable=SC2086
  set -- $glob
  if [ "$#" -eq 1 ] && [ "$1" = "$glob" ]; then
    log_sink__internal "prune: no matches for glob=$glob"
    return 0
  fi

  # Sort newest-first by mtime, drop beyond keep_n.
  # NOTE: filenames assumed no spaces (true for your naming).
  old_list=$(ls -1t $glob 2>/dev/null | awk -v n="$keep_n" 'NR>n') || old_list=""
  [ -n "$old_list" ] || return 0

  log_sink__internal "prune: deleting old logs for job=$job_name keep_n=$keep_n"

  old_IFS=$IFS
  IFS=$(printf '\n')
  set -- $old_list
  IFS=$old_IFS

  for f in "$@"; do
    [ -n "$f" ] || continue
    rm -f -- "$f" 2>/dev/null || log_sink__internal "prune: rm failed file=$f"
  done
}

log_sink_open() {
  # Open LOG_FILE on FD 3 (append digging)
  # If LOG_TRUNCATE=1, truncate first.
  if [ "${LOG_TRUNCATE:-0}" -ne 0 ] 2>/dev/null; then
    : >"$LOG_FILE" 2>/dev/null || return 1
  fi

  exec 3>>"$LOG_FILE" || return 1
  LOG_FD=3
  export LOG_FD
  return 0
}

log_sink_write_line() {
  line=$1
  [ -n "${LOG_FD:-}" ] || {
    log_sink__internal "write_line: LOG_FD unset (sink not opened?)"
    printf '%s\n' "ERR logger sink not initialized (LOG_FD unset)" >&2
    return 1
  }
  printf '%s\n' "$line" >&"$LOG_FD" || return 1
  return 0
}

log_sink_init() {
  if [ "${JOB_WRAP_ACTIVE:-0}" != "1" ]; then
    log_sink__internal "init: JOB_WRAP_ACTIVE!=1"
    printf '%s\n' "ERR log sink init called without JOB_WRAP_ACTIVE=1" >&2
    exit 2
  fi

  if [ -z "${JOB_NAME:-}" ]; then
    log_sink__internal "init: JOB_NAME empty"
    printf '%s\n' "ERR JOB_NAME is required for log sink" >&2
    exit 2
  fi

  if [ -z "${LOG_FILE:-}" ]; then
    log_sink__internal "init: LOG_FILE empty"
    printf '%s\n' "ERR LOG_FILE is required for log sink" >&2
    exit 2
  fi

  log_sink__ensure_dir "$LOG_FILE" || {
    log_sink__internal "init: mkdir failed for LOG_FILE=$LOG_FILE"
    printf '%s\n' "ERR cannot create log dir for $LOG_FILE" >&2
    exit 2
  }

  if [ -z "${LOG_LATEST:-}" ]; then
    log_dir=${LOG_FILE%/*}
    LOG_LATEST="${log_dir%/}/${JOB_NAME}-latest.log"
    export LOG_LATEST
  fi

  log_sink_open || {
    log_sink__internal "init: open failed LOG_FILE=$LOG_FILE"
    printf '%s\n' "ERR cannot open log file: $LOG_FILE" >&2
    exit 2
  }

  log_sink__update_latest "$LOG_FILE" "$LOG_LATEST"
  log_dir=${LOG_FILE%/*}
  log_sink__prune_keep_last_n "$log_dir" "$JOB_NAME" "${LOG_KEEP_COUNT:-10}"
}
