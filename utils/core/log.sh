#!/bin/sh
# utils/core/log.sh — Shared logging helper for POSIX shell scripts.
# Author: deadhedd
# License: MIT
#
# Heavy internal debug (opt-in):
#   LOG_INTERNAL_DEBUG=1            Enable internal debug messages
#   LOG_INTERNAL_DEBUG_FILE=<path>  Write internal debug to this file (else stderr)
#
# IMPORTANT: Internal debug NEVER writes to stdout.

# ------------------------------------------------------------------------------
# Load guard
# ------------------------------------------------------------------------------

if [ "${LOG_HELPER_LOADED:-0}" -eq 1 ] 2>/dev/null; then
  return 0 2>/dev/null || exit 0
fi
LOG_HELPER_LOADED=1

# ------------------------------------------------------------------------------
# Defaults (can be overridden by the environment before sourcing)
# ------------------------------------------------------------------------------

: "${LOG_INFO_STREAM:=stdout}"
: "${LOG_DEBUG_STREAM:=stdout}"

: "${LOG_ROOT:=${HOME:-/home/obsidian}/logs}"
: "${LOG_ROLLING_VAULT_ROOT:=${VAULT_PATH:-/home/obsidian/vaults/Main}}"
: "${LOG_LATEST_RELATIVE:=1}"

: "${LOG_ASCII_ONLY:=1}"
: "${LOG_TIMESTAMP:=1}"
: "${LOG_DEBUG:=0}"

# Internal debug: off by default
: "${LOG_INTERNAL_DEBUG:=0}"
: "${LOG_INTERNAL_DEBUG_FILE:=}"

# ------------------------------------------------------------------------------
# Time + sanitize
# ------------------------------------------------------------------------------

log__now() {
  if ! command -v date >/dev/null 2>&1; then
    return 1
  fi
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
# Internal debug emitter (never stdout)
# ------------------------------------------------------------------------------

log__dbg() {
  [ "${LOG_INTERNAL_DEBUG:-0}" -ne 0 ] || return 0

  ts=$(log__now 2>/dev/null || printf 'unknown')
  msg=$(log__sanitize "$*")
  line="$ts DBG $msg"

  if [ -n "${LOG_INTERNAL_DEBUG_FILE:-}" ]; then
    case "$LOG_INTERNAL_DEBUG_FILE" in
      */*)
        _dbg_dir=${LOG_INTERNAL_DEBUG_FILE%/*}
        if [ -n "$_dbg_dir" ] && [ ! -d "$_dbg_dir" ]; then
          mkdir -p "$_dbg_dir" 2>/dev/null || true
        fi
        ;;
    esac
    printf '%s\n' "$line" >>"$LOG_INTERNAL_DEBUG_FILE" 2>/dev/null || true
  else
    printf '%s\n' "$line" >&2
  fi
}

# Best-effort note of where this helper was sourced from.
# Set LOG_HELPER_PATH in the caller for an exact value.
log__dbg "log.sh loaded: pid=$$ LOG_HELPER_PATH=${LOG_HELPER_PATH:-<unset>} pwd=$(pwd 2>/dev/null || printf unknown)"

# ------------------------------------------------------------------------------
# Basic helpers
# ------------------------------------------------------------------------------

log__safe_job_name() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'
}

log__default_log_dir() {
  job_name=$1

  case "$job_name" in
    *daily-note*)
      dir="$LOG_ROOT/daily-notes"
      ;;
    *weekly-note*)
      dir="$LOG_ROOT/weekly-notes"
      ;;
    *monthly-note*|*quarterly-note*|*yearly-note*|*periodic-note*)
      dir="$LOG_ROOT/long-cycle"
      ;;
    *)
      dir="$LOG_ROOT/other"
      ;;
  esac

  printf '%s' "$dir"
}

log__latest_link_path() {
  log_file=$1
  job_name=${2:-${LOG_JOB_NAME:-log}}
  safe_job=$(log__safe_job_name "$job_name")

  case "$log_file" in
    */*) base_dir=${log_file%/*} ;;
    *)   base_dir="." ;;
  esac

  printf '%s/%s-latest.log' "$base_dir" "$safe_job"
}

# ------------------------------------------------------------------------------
# File append (instrumented)
# ------------------------------------------------------------------------------

log__append_file() {
  line=$1
  log_file=${LOG_FILE:-}

  if [ -z "$log_file" ]; then
    log__dbg "append: skipped (LOG_FILE unset) line_prefix=$(printf '%s' "$line" | cut -c1-60 2>/dev/null || printf '?')"
    return 0
  fi

  case "$log_file" in
    */*)
      dir=${log_file%/*}
      if [ -n "$dir" ] && [ ! -d "$dir" ]; then
        if ! mkdir -p "$dir" 2>/dev/null; then
          printf '%s\n' "ERR log: mkdir failed for $dir (LOG_FILE=$log_file)" >&2
          log__dbg "append: mkdir failed for dir=$dir LOG_FILE=$log_file"
          return 1
        fi
      fi
      ;;
  esac

  log__dbg "append: target=$log_file line_prefix=$(printf '%s' "$line" | cut -c1-60 2>/dev/null || printf '?')"

  if ! printf '%s\n' "$line" >>"$log_file" 2>/dev/null; then
    printf '%s\n' "ERR log: append failed (LOG_FILE=$log_file)" >&2
    log__dbg "append: FAILED target=$log_file"
    return 1
  fi

  return 0
}

# ------------------------------------------------------------------------------
# Rolling note path helpers
# ------------------------------------------------------------------------------

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

# ------------------------------------------------------------------------------
# Initialization & job lifecycle
# ------------------------------------------------------------------------------

log_init() {
  job_arg=${1:-}

  if [ "${LOG_INIT_DONE:-0}" -eq 1 ] 2>/dev/null; then
    export LOG_ROOT LOG_FILE LOG_RUN_TS LOG_JOB_NAME LOG_LATEST_LINK LOG_ROLLING_VAULT_ROOT
    log__dbg "log_init: already done LOG_FILE=${LOG_FILE:-<unset>}"
    return 0
  fi

  LOG_INIT_DONE=1

  : "${LOG_ROOT:=${HOME:-/home/obsidian}/logs}"
  : "${LOG_ROLLING_VAULT_ROOT:=${VAULT_PATH:-/home/obsidian/vaults/Main}}"

  if [ -n "$job_arg" ] && [ -z "${LOG_JOB_NAME:-}" ]; then
    LOG_JOB_NAME=$job_arg
  elif [ -z "${LOG_JOB_NAME:-}" ]; then
    LOG_JOB_NAME=${0##*/}
  fi

  if [ -z "${LOG_RUN_TS:-}" ]; then
    if ts=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null); then
      LOG_RUN_TS=$ts
    elif ts=$(log__now 2>/dev/null); then
      LOG_RUN_TS=$(printf '%s' "$ts" | tr -d ':-')
    fi
  fi
  : "${LOG_RUN_TS:=run}"

  safe_job=$(log__safe_job_name "${LOG_JOB_NAME:-job}")

  # FIX: Only truncate when log_init created the LOG_FILE path (i.e., LOG_FILE was unset).
  created_new_log_file=0
  if [ -z "${LOG_FILE:-}" ]; then
    log_dir=$(log__default_log_dir "$safe_job")
    LOG_FILE="${log_dir}/${safe_job}-${LOG_RUN_TS}.log"
    created_new_log_file=1
  fi

  log__dbg "log_init: pid=$$ job=$LOG_JOB_NAME safe_job=$safe_job run_ts=$LOG_RUN_TS LOG_FILE=$LOG_FILE created_new=$created_new_log_file"

  case "$LOG_FILE" in
    */*)
      target_dir=${LOG_FILE%/*}
      if [ -n "$target_dir" ] && [ ! -d "$target_dir" ]; then
        mkdir -p "$target_dir" 2>/dev/null || true
      fi
      ;;
  esac

  if [ "$created_new_log_file" -ne 0 ] 2>/dev/null; then
    : >"$LOG_FILE" 2>/dev/null || true
  fi
  log__append_file "INFO log_init: opened LOG_FILE=$LOG_FILE" || true

  LOG_LATEST_LINK=${LOG_LATEST_LINK:-$(log__latest_link_path "$LOG_FILE" "$safe_job")}

  export LOG_ROOT LOG_FILE LOG_RUN_TS LOG_JOB_NAME LOG_LATEST_LINK LOG_ROLLING_VAULT_ROOT
}

log_start_job() {
  job_arg=${1:-${LOG_JOB_NAME:-job}}
  shift 2>/dev/null || true

  safe_job=$(log__safe_job_name "$job_arg")
  LOG_JOB_NAME=$safe_job
  LOG_RUN_TS=${LOG_RUN_TS:-$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || log__now 2>/dev/null || printf 'run')}
  LOG_RUN_START_SEC=${LOG_RUN_START_SEC:-$(date -u +%s 2>/dev/null || printf '')}

  log_init "$safe_job"

  log__dbg "start_job: job=$safe_job LOG_FILE=${LOG_FILE:-<unset>} start_sec=${LOG_RUN_START_SEC:-<unset>}"

  log_info "== ${safe_job} start =="
  log_info "utc_start=$LOG_RUN_TS"

  while [ $# -gt 0 ]; do
    log_info "$1"
    shift
  done

  log_info "log_file=${LOG_FILE:-unknown}"
  log_info "------------------------------"
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

  old_list=$(ls -1t "$log_dir/${safe_job}-"*.log 2>/dev/null | awk -v n="$keep" 'NR>n')
  if [ -n "${old_list:-}" ]; then
    printf '%s\n' "$old_list" | xargs rm -f
  fi
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

  ln -sf "$target_path" "$link_path" 2>/dev/null || true
}

log_finish_job() {
  status=$1
  start_sec=${2:-${LOG_RUN_START_SEC:-}}

  end_ts=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || log__now 2>/dev/null || printf 'unknown')
  duration=""
  rolling_note_path=$(log__rolling_note_path "${LOG_FILE:-}" 2>/dev/null || printf '')

  if [ -n "$start_sec" ]; then
    end_sec=$(date -u +%s 2>/dev/null || printf '')
    if [ -n "$end_sec" ]; then
      duration=$(( end_sec - start_sec ))
    fi
  fi

  safe_job=$(log__safe_job_name "${LOG_JOB_NAME:-job}")

  log_info "------------------------------"
  log_info "exit=$status"
  log_info "utc_end=$end_ts"
  if [ -n "$duration" ]; then
    log_info "duration_seconds=$duration"
  fi
  log_info "== ${safe_job} end =="

  log_update_latest_link
  log_rotate

  rolling_status=0
  if log_update_rolling_note; then
    if [ -n "$rolling_note_path" ]; then
      log_info "Rolling log updated: $rolling_note_path"
    fi
  else
    rolling_status=$?
    if [ -n "$rolling_note_path" ]; then
      log_err "Rolling log update failed: $rolling_note_path (exit=$rolling_status)"
    else
      log_err "Rolling log update failed (exit=$rolling_status)"
    fi
  fi

  if [ "$status" -eq 0 ] 2>/dev/null && [ "$rolling_status" -ne 0 ] 2>/dev/null; then
    status=$rolling_status
  fi

  return "$status"
}

# ------------------------------------------------------------------------------
# Streaming & command capture
# ------------------------------------------------------------------------------

log__emit_line() {
  line=$1

  set -- $line

  level=""
  msg="$line"

  if [ $# -gt 0 ]; then
    case "$1" in
      INFO|WARN|ERR|DEBUG)
        level=$1
        shift
        msg=$*
        ;;
    esac
  fi

  if [ -z "$level" ] && [ $# -gt 1 ]; then
    case "$2" in
      INFO|WARN|ERR|DEBUG)
        level=$2
        shift 2
        msg=$*
        ;;
    esac
  fi

  case "$level" in
    WARN)  log_warn "$msg"  ;;
    ERR)   log_err "$msg"   ;;
    DEBUG) log_debug "$msg" ;;
    *)     log_info "$line" ;;
  esac
}

log_stream_file() {
  log_source=$1

  while IFS= read -r line || [ -n "$line" ]; do
    log__emit_line "$line"
  done <"$log_source"
}

log_run_with_capture() {
  tmp_log=$(mktemp 2>/dev/null || mktemp "/tmp/log.${LOG_JOB_NAME:-job}.XXXXXX" 2>/dev/null || printf '')

  if [ -z "$tmp_log" ]; then
    log_err "mktemp failed (cannot capture job output)"
    return 127
  fi

  cleanup_tmp_log() {
    [ -f "$tmp_log" ] || return 0
    rm -f -- "$tmp_log"
  }

  trap 'cleanup_tmp_log' EXIT HUP INT TERM

  status=0
  set +e
  "$@" >"$tmp_log" 2>&1
  status=$?
  set -e

  log_stream_file "$tmp_log"

  cleanup_tmp_log
  trap - EXIT HUP INT TERM

  return "$status"
}

log_run_job() {
  job_name=${1:-}
  shift

  [ -n "$job_name" ] || {
    log_err "log_run_job: missing job name"
    return 2
  }

  context_args=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --)
        shift
        break
        ;;
      *)
        if [ -n "$context_args" ]; then
          context_args="$context_args|$1"
        else
          context_args="$1"
        fi
        shift
        ;;
    esac
  done

  if [ $# -eq 0 ]; then
    log_err "log_run_job: missing command to run"
    return 2
  fi

  command_args=$(printf '%s\n' "$@")

  if [ -n "$context_args" ]; then
    old_IFS=$IFS
    IFS='|'
    set -- $context_args
    IFS=$old_IFS
    log_start_job "$job_name" "$@"
  else
    log_start_job "$job_name"
  fi

  old_IFS=$IFS
  NL='
'
  IFS=$NL
  set -- $command_args
  IFS=$old_IFS

  status=0
  if ! log_run_with_capture "$@"; then
    status=$?
  fi

  log_finish_job "$status"

  return "$status"
}

# ------------------------------------------------------------------------------
# Public logging API
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

  log__append_file "$line"
}

log_info()  { log__emit INFO  "${LOG_INFO_STREAM:-stdout}" "$@"; }
log_warn()  { log__emit WARN  stderr "$@"; }
log_err()   { log__emit ERR   stderr "$@"; }
log_debug() {
  if [ "${LOG_DEBUG:-0}" -ne 0 ]; then
    log__emit DEBUG "${LOG_DEBUG_STREAM:-stdout}" "$@"
  fi
}
