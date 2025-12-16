#!/bin/sh
# utils/core/log.sh — Shared logging helper for POSIX shell scripts.
# Author: deadhedd
# License: MIT
#
# IMPORTANT:
# - INFO / DEBUG default to stderr (safe for data pipelines)
# - Captured command output is ALWAYS emitted to stderr
#
# Heavy internal debug (opt-in):
#   LOG_INTERNAL_DEBUG=1
#   LOG_INTERNAL_DEBUG_FILE=<path>

# ------------------------------------------------------------------------------
# Load guard
# ------------------------------------------------------------------------------
# This file is a library and must be sourced.
# If executed by mistake, fail loudly.
(return 0 2>/dev/null) || { printf 'ERR utils/core/log.sh must be sourced, not executed\n' >&2; exit 2; }

if [ "${LOG_HELPER_LOADED:-0}" -eq 1 ]; then
  return 0
fi
LOG_HELPER_LOADED=1

# ------------------------------------------------------------------------------
# Defaults (safe-by-default)
# ------------------------------------------------------------------------------

: "${LOG_INFO_STREAM:=stderr}"
: "${LOG_DEBUG_STREAM:=stderr}"

: "${LOG_ROOT:=${HOME:-/home/obsidian}/logs}"
: "${LOG_ROLLING_VAULT_ROOT:=${VAULT_PATH:-/home/obsidian/vaults/Main}}"
: "${LOG_LATEST_RELATIVE:=1}"

: "${LOG_ASCII_ONLY:=1}"
: "${LOG_TIMESTAMP:=1}"
: "${LOG_DEBUG:=0}"

# Captured command output is NEVER stdout
: "${LOG_CAPTURE_STREAM:=stderr}"

# Internal debug
: "${LOG_INTERNAL_DEBUG:=0}"
: "${LOG_INTERNAL_DEBUG_FILE:=}"

# ------------------------------------------------------------------------------
# Time + sanitize
# ------------------------------------------------------------------------------

log__now() {
  command -v date >/dev/null 2>&1 || return 1
  date '+%Y-%m-%dT%H:%M:%S%z'
}

log__sanitize() {
  if [ "${LOG_ASCII_ONLY:-1}" -ne 0 ]; then
    printf '%s' "$*" | LC_ALL=C tr -cd '\11\12\15\40-\176'
  else
    printf '%s' "$*"
  fi
}

# ------------------------------------------------------------------------------
# Internal debug (never stdout)
# ------------------------------------------------------------------------------

log__dbg() {
  [ "${LOG_INTERNAL_DEBUG:-0}" -ne 0 ] || return 0

  ts=$(log__now 2>/dev/null || printf 'unknown')
  msg=$(log__sanitize "$*")
  line="$ts DBG $msg"

  if [ -n "${LOG_INTERNAL_DEBUG_FILE:-}" ]; then
    case "$LOG_INTERNAL_DEBUG_FILE" in
      */*)
        d=${LOG_INTERNAL_DEBUG_FILE%/*}
        [ -d "$d" ] || mkdir -p "$d" || return 1
        ;;
    esac
    printf '%s\n' "$line" >>"$LOG_INTERNAL_DEBUG_FILE" 2>/dev/null || return 1
  else
    printf '%s\n' "$line" >&2
  fi
}

log__dbg "log.sh loaded: pid=$$ LOG_HELPER_PATH=${LOG_HELPER_PATH:-<unset>}"

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

log__safe_job_name() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'
}

log__default_log_dir() {
  case "$1" in
    *daily-note*)   printf '%s' "$LOG_ROOT/daily-notes" ;;
    *weekly-note*)  printf '%s' "$LOG_ROOT/weekly-notes" ;;
    *monthly-note*|*quarterly-note*|*yearly-note*|*periodic-note*)
                     printf '%s' "$LOG_ROOT/long-cycle" ;;
    *)              printf '%s' "$LOG_ROOT/other" ;;
  esac
}

log__latest_link_path() {
  log_file=$1
  job=${2:-${LOG_JOB_NAME:-log}}
  safe=$(log__safe_job_name "$job")

  case "$log_file" in
    */*) base=${log_file%/*} ;;
    *)   base=. ;;
  esac

  printf '%s/%s-latest.log' "$base" "$safe"
}

# ------------------------------------------------------------------------------
# File append
# ------------------------------------------------------------------------------

log__append_file() {
  line=$1
  [ -n "${LOG_FILE:-}" ] || return 0

  case "${LOG_FILE}" in
    */*)
      d=${LOG_FILE%/*}
      [ -d "$d" ] || mkdir -p "$d" 2>/dev/null || return 1
      ;;
  esac

  printf '%s\n' "$line" >>"$LOG_FILE" 2>/dev/null || {
    printf 'ERR log append failed (%s)\n' "$LOG_FILE" >&2
    return 1
  }
}

# ------------------------------------------------------------------------------
# Init / lifecycle
# ------------------------------------------------------------------------------

log_init() {
  [ "${LOG_INIT_DONE:-0}" -eq 0 ] || return 0

  LOG_JOB_NAME=${LOG_JOB_NAME:-${1:-${0##*/}}}

  if [ -z "${LOG_RUN_TS:-}" ]; then
    LOG_RUN_TS=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || printf run)
  fi

  safe=$(log__safe_job_name "$LOG_JOB_NAME")

  if [ -z "${LOG_FILE:-}" ]; then
    dir=$(log__default_log_dir "$safe")
    LOG_FILE="$dir/$safe-$LOG_RUN_TS.log"
  fi

  case "${LOG_FILE}" in
    */*)
      LOG_DIR_PATH=${LOG_FILE%/*}
      if [ ! -d "$LOG_DIR_PATH" ]; then
        mkdir -p "$LOG_DIR_PATH" 2>/dev/null || return 1
      fi
      ;;
  esac

  : >"$LOG_FILE" 2>/dev/null || return 1

  LOG_LATEST_LINK=${LOG_LATEST_LINK:-$(log__latest_link_path "$LOG_FILE" "$safe")}

  export LOG_FILE LOG_JOB_NAME LOG_RUN_TS LOG_LATEST_LINK LOG_ROOT LOG_ROLLING_VAULT_ROOT

  log__append_file "INFO log_init: opened LOG_FILE=$LOG_FILE" || return 1

  LOG_INIT_DONE=1
}

log_start_job() {
  job=$1
  shift || true

  LOG_JOB_NAME=$(log__safe_job_name "$job")
  LOG_RUN_START_SEC=$(date -u +%s 2>/dev/null || printf '')
  export LOG_JOB_NAME LOG_RUN_START_SEC

  log_init "$LOG_JOB_NAME"

  log_info "== ${LOG_JOB_NAME} start =="
  log_info "utc_start=$LOG_RUN_TS"
  while [ $# -gt 0 ]; do log_info "$1"; shift; done
  log_info "log_file=$LOG_FILE"
  log_info "------------------------------"
}

# ------------------------------------------------------------------------------
# Rolling note, rotate, latest (unchanged behavior)
# ------------------------------------------------------------------------------

# (UNCHANGED: your existing implementations are correct and safe)
# log__rolling_note_path
# log_update_rolling_note
# log_rotate
# log_update_latest_link

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

  mapped_root="${LOG_ROLLING_VAULT_ROOT%/}/Server Logs"

  case "$log_file" in
    */logs/*) rel_path=${log_file#*/logs/} ;;
    *)        rel_path=${log_file##*/} ;;
  esac

  case "$rel_path" in
    */*) rel_dir=${rel_path%/*} ;;
    *)   rel_dir= ;;
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
  [ -n "$log_file" ] || return 0

  rolling_path=$(log__rolling_note_path "$log_file") || return 0
  [ -n "$rolling_path" ] || return 0

  case "$rolling_path" in
    */*)
      rolling_dir=${rolling_path%/*}
      if [ ! -d "$rolling_dir" ]; then
        mkdir -p "$rolling_dir" 2>/dev/null || return 1
      fi
      ;;
  esac

  tmp_path="${rolling_path}.tmp"

  ts=$(log__now 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || printf 'unknown')
  job_title=${LOG_JOB_NAME:-Latest Log}

  log__dbg "rolling_note: from=$log_file to=$rolling_path"

  if ! {
    printf '# %s\n\n' "$job_title"
    printf 'Source: `%s`\n' "$log_file"
    printf 'Timestamp: %s\n\n' "$ts"
    printf '```text\n'
    if [ -n "${LOG_ROLLING_LINES:-}" ]; then
      if ! tail -n "$LOG_ROLLING_LINES" "$log_file" 2>/dev/null; then
        tail -"$LOG_ROLLING_LINES" "$log_file" 2>/dev/null || return 1
      fi
    else
      cat "$log_file" || return 1
    fi
    printf '\n```\n'
  } >"$tmp_path"; then
    return 1
  fi

  mv "$tmp_path" "$rolling_path" || return 1
}

log_rotate() {
  keep_arg=${1:-}
  keep=${keep_arg:-${LOG_KEEP:-20}}
  log_file=${LOG_FILE:-}
  job_name=${LOG_JOB_NAME:-}

  [ -n "$log_file" ] || return 0

  case "$log_file" in
    */*) log_dir=${log_file%/*} ;;
    *)   return 0 ;;
  esac

  if [ -z "$job_name" ]; then
    base_name=${log_file##*/}
    job_name=${base_name%-*}
  fi

  safe_job=$(log__safe_job_name "$job_name")

  set -- "$log_dir"/${safe_job}-*.log

  if [ $# -eq 1 ] && [ "$1" = "$log_dir/${safe_job}-"*.log ]; then
    return 0
  fi

  if ! old_list=$(ls -1t "$@" 2>/dev/null | awk -v n="$keep" 'NR>n'); then
    return 1
  fi

  [ -n "${old_list:-}" ] || return 0

  old_IFS=$IFS
  IFS=$(printf '\n')
  set -- $old_list
  IFS=$old_IFS

  for old_log in "$@"; do
    [ -n "$old_log" ] || continue
    rm -f -- "$old_log" || return 1
  done
}

log_update_latest_link() {
  log_file=${LOG_FILE:-}
  link_path=${LOG_LATEST_LINK:-}

  if [ -z "$log_file" ] || [ -z "$link_path" ]; then
    return 0
  fi

  case "$link_path" in
    */*)
      link_dir=${link_path%/*}
      if [ -n "$link_dir" ] && [ ! -d "$link_dir" ]; then
        mkdir -p "$link_dir" 2>/dev/null || return 1
      fi
      ;;
  esac

  target_path=$log_file
  if [ "${LOG_LATEST_RELATIVE:-1}" -ne 0 ]; then
    case "$log_file" in
      */*) log_dir=${log_file%/*} ;;
      *)   log_dir="." ;;
    esac

    case "$link_path" in
      */*) link_dir=${link_path%/*} ;;
      *)   link_dir="." ;;
    esac

    if [ "$log_dir" = "$link_dir" ]; then
      target_path=$(basename "$log_file")
    fi
  fi

  ln -sf "$target_path" "$link_path" 2>/dev/null || return 1
}

# ------------------------------------------------------------------------------
# Finish
# ------------------------------------------------------------------------------

log_finish_job() {
  status=$1

  end_ts=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || printf unknown)

  log_info "------------------------------"
  log_info "exit=$status"
  log_info "utc_end=$end_ts"
  log_info "== ${LOG_JOB_NAME} end =="

  log_update_latest_link || return 1
  log_rotate || return 1
  log_update_rolling_note || return 1

  return "$status"
}

# ------------------------------------------------------------------------------
# Streaming & capture (FIXED)
# ------------------------------------------------------------------------------

log__emit_line() {
  line=$1

  level=""
  msg="$line"

  case "$line" in
    INFO|INFO\ *) level=INFO ;;
    WARN|WARN\ *) level=WARN ;;
    ERR|ERR\ *) level=ERR ;;
    DEBUG|DEBUG\ *) level=DEBUG ;;
  esac

  if [ -n "$level" ]; then
    msg=${line#"$level"}
    case "$msg" in
      " "*) msg=${msg# } ;;
    esac
  fi

  case "$level" in
    INFO)  log_info  "$msg" ;;
    WARN)  log_warn  "$msg" ;;
    ERR)   log_err   "$msg" ;;
    DEBUG) log_debug "$msg" ;;
    *)
      # Captured command output → ALWAYS stderr
      log__emit INFO "${LOG_CAPTURE_STREAM:-stderr}" "$line"
      ;;
  esac
}

log_stream_file() {
  while IFS= read -r line || [ -n "$line" ]; do
    log__emit_line "$line"
  done <"$1"
}

log_run_with_capture() {
  tmp=$(mktemp 2>/dev/null || mktemp "/tmp/log.${LOG_JOB_NAME:-job}.XXXXXX") || {
    log_err "mktemp failed"
    return 127
  }

  set +e
  "$@" >"$tmp" 2>&1
  status=$?
  set -e

  log_stream_file "$tmp"
  rm -f "$tmp"

  return "$status"
}

log_run_job() {
  job_name=${1:-}
  shift

  [ -n "$job_name" ] || {
    log_err "log_run_job: missing job name"
    return 2
  }

  LOG_JOB_NAME=$(log__safe_job_name "$job_name")
  LOG_RUN_START_SEC=$(date -u +%s 2>/dev/null || printf '')
  export LOG_JOB_NAME LOG_RUN_START_SEC

  log_init "$LOG_JOB_NAME"

  log_info "== ${LOG_JOB_NAME} start =="
  log_info "utc_start=$LOG_RUN_TS"

  while [ $# -gt 0 ]; do
    case "$1" in
      --)
        shift
        break
        ;;
      *)
        log_info "$1"
        shift
        ;;
    esac
  done

  if [ $# -eq 0 ]; then
    log_err "log_run_job: missing command to run"
    return 2
  fi

  log_info "log_file=$LOG_FILE"
  log_info "------------------------------"

  status=0
  if ! log_run_with_capture "$@"; then
    status=$?
  fi

  log_finish_job "$status"

  return "$status"
}

# ------------------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------------------

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
    *)      printf '%s\n' "$line" ;;
  esac

  log__append_file "$line" || return 1
}

log_info()  { log__emit INFO  "${LOG_INFO_STREAM:-stderr}" "$@"; }
log_warn()  { log__emit WARN  stderr "$@"; }
log_err()   { log__emit ERR   stderr "$@"; }
log_debug() {
  [ "${LOG_DEBUG:-0}" -ne 0 ] && log__emit DEBUG "${LOG_DEBUG_STREAM:-stderr}" "$@"
}
