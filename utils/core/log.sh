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

log__format_dir_segment() {
  segment=$1
  cleaned=$(printf '%s' "$segment" | tr '-' ' ')
  printf '%s' "$cleaned" |
    awk '{ for (i = 1; i <= NF; i++) { $i = toupper(substr($i,1,1)) substr($i,2) } printf "%s", $0 }'
}

log__rolling_note_path() {
  [ -n "${LOG_ROLLING_VAULT_ROOT:-}" ] || return 1

  log_file=${1:-${LOG_FILE:-}}
  [ -n "$log_file" ] || return 1

  safe_job=$(log__safe_job_name "${LOG_JOB_NAME:-}")

  if [ -z "$safe_job" ]; then
    base_name=${log_file##*/}
    base_trimmed=${base_name%.log}
    safe_job=$(log__safe_job_name "${base_trimmed%-*}")
  fi

  [ -n "$safe_job" ] || safe_job=log

  mapped_root=${LOG_ROLLING_VAULT_ROOT%/}/Server Logs

  case "$log_file" in
    */logs/*)
      rel_path=${log_file#*/logs/}
      ;;
    *)
      rel_path=${log_file##*/}
      ;;
  esac

  case "$rel_path" in
    */*)
      rel_dir=${rel_path%/*}
      ;;
    *)
      rel_dir=
      ;;
  esac

  mapped_dir=$mapped_root

  if [ -n "$rel_dir" ]; then
    old_ifs=$IFS
    IFS='/'
    set -- $rel_dir
    IFS=$old_ifs

    for segment in "$@"; do
      formatted=$(log__format_dir_segment "$segment")
      mapped_dir="$mapped_dir/$formatted"
    done
  fi

  printf '%s/%s-latest.md' "$mapped_dir" "$safe_job"
}

log_update_rolling_note() {
  [ -n "${LOG_ROLLING_VAULT_ROOT:-}" ] || return 0

  log_file=${LOG_FILE:-}
  if [ "${LOG_FILE_MAPPED:-0}" -ne 1 ]; then
    log_file=$(log__periodic_log_path "$log_file")
  fi
  [ -n "$log_file" ] || return 0

  rolling_path=$(log__rolling_note_path "$log_file") || return 0
  [ -n "$rolling_path" ] || return 0

  case "$rolling_path" in
    */*)
      rolling_dir=${rolling_path%/*}
      if [ ! -d "$rolling_dir" ]; then
        mkdir -p "$rolling_dir" || return 1
      fi
      ;;
  esac

  tmp_path="${rolling_path}.tmp"

  ts=$(log__now 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || printf 'unknown')
  job_title=${LOG_JOB_NAME:-Latest Log}

  {
    printf '# %s\n\n' "$job_title"
    printf 'Source: `%s`\n' "$log_file"
    printf 'Timestamp: %s\n\n' "$ts"
    printf '```text\n'
    if [ -n "${LOG_ROLLING_LINES:-}" ]; then
      if ! tail -n "$LOG_ROLLING_LINES" "$log_file" 2>/dev/null; then
        tail -"$LOG_ROLLING_LINES" "$log_file" 2>/dev/null || true
      fi
    else
      cat "$log_file" 2>/dev/null || true
    fi
    printf '\n```\n'
  } >"$tmp_path" && mv "$tmp_path" "$rolling_path"
}

log_rotate() {
  keep_arg=${1:-}
  keep=${keep_arg:-${LOG_KEEP:-20}}
  log_file=${LOG_FILE:-}
  if [ "${LOG_FILE_MAPPED:-0}" -ne 1 ]; then
    log_file=$(log__periodic_log_path "$log_file")
  fi
  job_name=${LOG_JOB_NAME:-}

  [ -n "$log_file" ] || return 0

  case "$log_file" in
    */*)
      log_dir=${log_file%/*}
      ;;
    *)
      return 0
      ;;
  esac

  if [ -z "$job_name" ]; then
    base_name=${log_file##*/}
    job_name=${base_name%-*}
  fi

  safe_job=$(log__safe_job_name "$job_name")

  old_list=$(ls -1t "$log_dir/${safe_job}-"*.log 2>/dev/null | awk -v n="$keep" 'NR>n')
  if [ -n "${old_list:-}" ]; then
    printf '%s\n' "$old_list" | xargs rm -f
  fi
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
