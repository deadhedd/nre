#!/bin/sh
# utils/core/log.sh — Shared logging helper for POSIX shell scripts.
# Author: deadhedd
# License: MIT

# This helper is intended to be sourced. Avoid redefining if already loaded.
if [ "${LOG_HELPER_LOADED:-0}" -eq 1 ] 2>/dev/null; then
  return 0 2>/dev/null || exit 0
fi
LOG_HELPER_LOADED=1

: "${LOG_INFO_STREAM:=stdout}"
: "${LOG_DEBUG_STREAM:=stdout}"

log__safe_job_name() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'
}

log__default_log_dir() {
  log_root=${LOG_ROOT:-${HOME:-/home/obsidian}/logs}
  job_name=$1

  case "$job_name" in
    *daily-note*)
      dir="$log_root/daily-notes"
      ;;
    *weekly-note*)
      dir="$log_root/weekly-notes"
      ;;
    *monthly-note*|*quarterly-note*|*yearly-note*|*periodic-note*)
      dir="$log_root/periodic-notes"
      ;;
    *)
      dir="$log_root/other"
      ;;
  esac

  printf '%s' "$dir"
}

log_init() {
  job_arg=${1:-}

  if [ "${LOG_INIT_DONE:-0}" -eq 1 ] 2>/dev/null; then
    export LOG_ROOT LOG_FILE LOG_RUN_TS LOG_JOB_NAME
    return 0
  fi

  LOG_INIT_DONE=1

  : "${LOG_ROOT:=${HOME:-/home/obsidian}/logs}"

  if [ -n "$job_arg" ] && [ -z "${LOG_JOB_NAME:-}" ]; then
    LOG_JOB_NAME=$job_arg
  elif [ -z "${LOG_JOB_NAME:-}" ]; then
    LOG_JOB_NAME=${0##*/}
  fi

  if [ -z "${LOG_RUN_TS:-}" ]; then
    if ts=$(date +%Y%m%dT%H%M%S%z 2>/dev/null); then
      LOG_RUN_TS=$ts
    elif ts=$(log__now 2>/dev/null); then
      LOG_RUN_TS=$(printf '%s' "$ts" | tr -d ':-')
    fi
  fi
  : "${LOG_RUN_TS:=run}"

  safe_job=$(log__safe_job_name "${LOG_JOB_NAME:-job}")

  if [ -z "${LOG_FILE:-}" ]; then
    log_dir=$(log__default_log_dir "$safe_job")
    LOG_FILE="${log_dir}/${safe_job}-${LOG_RUN_TS}.log"

    target=$(log__periodic_log_path "$LOG_FILE")
    case "$target" in
      */*)
        target_dir=${target%/*}
        if [ -n "$target_dir" ] && [ ! -d "$target_dir" ]; then
          mkdir -p "$target_dir" || true
        fi
        ;;
    esac

    : >"$target" 2>/dev/null || true
  fi

  export LOG_ROOT LOG_FILE LOG_RUN_TS LOG_JOB_NAME
}

# Emit a timestamp in local time when enabled. Default is on; set LOG_TIMESTAMP=0 to disable.
log__now() {
  if ! command -v date >/dev/null 2>&1; then
    return 1
  fi
  date '+%Y-%m-%dT%H:%M:%S%z'
}

# Sanitize messages when ASCII-only logs are required (default on).
log__sanitize() {
  if [ "${LOG_ASCII_ONLY:-1}" -ne 0 ]; then
    # Allow horizontal tab, LF, CR, and printable ASCII.
    printf '%s' "$*" | LC_ALL=C tr -cd '\11\12\15\40-\176'
  else
    printf '%s' "$*"
  fi
}

log__periodic_log_path() {
  path=$1
  mapped_path=$path

  case "$path" in
    */logs/daily-notes/*)
      base_name=${path##*/}
      root_dir=${path%/daily-notes/*}
      mapped_path="$root_dir/Periodic/Daily/$base_name"
      ;;
    */logs/weekly-notes/*)
      base_name=${path##*/}
      root_dir=${path%/weekly-notes/*}
      mapped_path="$root_dir/Periodic/Weekly/$base_name"
      ;;
    */logs/periodic-notes/*)
      base_name=${path##*/}
      root_dir=${path%/periodic-notes/*}
      cycle_dir=""
      case "$base_name" in
        *monthly*) cycle_dir="Monthly" ;;
        *quarter*) cycle_dir="Quarterly" ;;
        *yearly*) cycle_dir="Yearly" ;;
      esac

      if [ -n "$cycle_dir" ]; then
        mapped_path="$root_dir/Periodic/Long Cycle/$cycle_dir/$base_name"
      else
        mapped_path="$root_dir/Periodic/Long Cycle/$base_name"
      fi
      ;;
    */logs/*)
      base_name=${path##*/}
      root_dir=${path%/logs/*}/logs
      mapped_path="$root_dir/other/$base_name"
      ;;
  esac

  printf '%s' "$mapped_path"
}

log__append_file() {
  line=$1
  log_file=${LOG_FILE:-}
  [ -n "$log_file" ] || return 0

  if [ "${LOG_FILE_MAPPED:-0}" -ne 1 ]; then
    log_file=$(log__periodic_log_path "$log_file")
  fi

  case "$log_file" in
    */*)
      dir=${log_file%/*}
      if [ -n "$dir" ] && [ ! -d "$dir" ]; then
        mkdir -p "$dir" || return 1
      fi
      ;;
  esac

  printf '%s\n' "$line" >>"$log_file"
}

log__emit() {
  level=$1
  stream=$2
  shift 2
  msg=$(log__sanitize "$*")

  if [ "${LOG_TIMESTAMP:-1}" -ne 0 ] && ts=$(log__now 2>/dev/null); then
    line="$ts $level $msg"
  else
    line="$level $msg"
  fi

  case "$stream" in
    stderr) printf '%s\n' "$line" >&2 ;;
    *) printf '%s\n' "$line" ;;
  esac

  log__append_file "$line"
}

log_info() { log__emit INFO "${LOG_INFO_STREAM:-stdout}" "$@"; }
log_warn() { log__emit WARN stderr "$@"; }
log_err()  { log__emit ERR stderr "$@"; }
log_debug() {
  if [ "${LOG_DEBUG:-0}" -ne 0 ]; then
    log__emit DEBUG "${LOG_DEBUG_STREAM:-stdout}" "$@"
  fi
}
