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
# Load guard (library-only; MUST be sourced)
#
# Problem:
#   POSIX sh provides no explicit, portable way to distinguish "sourced" vs
#   "executed" scripts.
#
# Chosen invariant:
#   - `return` succeeds ONLY when this file is being sourced (or inside a function).
#   - If executed, `return` raises an error.
#
# Behavioral contract:
#   - If executed directly: emit a clear error to stderr and exit 2.
#   - If sourced: continue silently.
#   - Never writes to stdout.
#
# Rationale:
#   The `return` probe is the least-bad, portable option across sh/dash/ksh/ash.
#   Alternatives are either non-portable, unreliable, or noisier.
#
# This behavior is intentional. Do not "simplify" unless POSIX grows a real signal.
# ------------------------------------------------------------------------------
# Invariant: `return` is valid only when this file is being sourced (or inside a
# function). If executed as a script, `return` errors and we fail loudly.
(return 0 2>/dev/null) || {
  printf 'ERR utils/core/log.sh must be sourced, not executed\n' >&2
  exit 2
}

# Some shells allow `return` in a subshell even when executed directly. Fall back
# to a basename check to keep execution-mode errors loud and consistent.
case ${0##*/} in
  log.sh)
    printf 'ERR utils/core/log.sh must be sourced, not executed\n' >&2
    exit 2
    ;;
esac

# Load-once guard
if [ "${LOG_HELPER_LOADED:-0}" -eq 1 ]; then
  return 0
fi
LOG_HELPER_LOADED=1

log__helper_dir=${LOG_HELPER_DIR:-}

if [ -z "$log__helper_dir" ]; then
  printf 'ERR log.sh: LOG_HELPER_DIR must be set for helper resolution\n' >&2
  return 1
fi

if log__helper_dir=$(CDPATH= cd -- "$log__helper_dir" 2>/dev/null && pwd -P); then
  :
else
  printf 'ERR log.sh: unable to resolve helper directory (%s)\n' "$log__helper_dir" >&2
  return 1
fi

LOG_HELPER_DIR=$log__helper_dir
export LOG_HELPER_DIR

log__date_helper_path="$log__helper_dir/date-period-helpers.sh"

if [ ! -f "$log__date_helper_path" ]; then
  printf 'ERR log.sh: missing date helper (%s)\n' "$log__date_helper_path" >&2
  return 1
fi

. "$log__date_helper_path" || {
  printf 'ERR log.sh: failed to load date helper (%s)\n' "$log__date_helper_path" >&2
  return 1
}

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
: "${LOG_CAPTURE_LEVEL:=OUT}"
: "${LOG_CAPTURE_STREAM:=stderr}"

# Internal debug
: "${LOG_INTERNAL_DEBUG:=0}"
: "${LOG_INTERNAL_DEBUG_FILE:=}"

# ------------------------------------------------------------------------------
# Time + sanitize
# ------------------------------------------------------------------------------

log__now_local_iso() {
  get_local_iso_timestamp
}

log__now_utc_runid() {
  get_utc_run_id
}

log__now_utc_epoch() {
  get_utc_epoch_seconds
}

log__sanitize() {
  if [ "${LOG_ASCII_ONLY:-1}" -ne 0 ]; then
    printf '%s' "$*" | LC_ALL=C tr -cd '\11\12\15\40-\176'
  else
    printf '%s' "$*"
  fi
}

log__format_line() {
  log__level=$1
  shift
  log__msg=$*

  if [ "${LOG_TIMESTAMP:-1}" -ne 0 ] && log__ts=$(log__now_local_iso 2>/dev/null); then
    log__ts_field=$log__ts
  else
    log__ts_field='-'
  fi

  printf '%s %s %s' "$log__ts_field" "$log__level" "$log__msg"
}

# ------------------------------------------------------------------------------
# Internal debug (never stdout)
# ------------------------------------------------------------------------------

log__dbg() {
  [ "${LOG_INTERNAL_DEBUG:-0}" -ne 0 ] || return 0

  log__msg=$(log__sanitize "$*")
  log__line=$(log__format_line "DBG" "$log__msg")

  if [ -n "${LOG_INTERNAL_DEBUG_FILE:-}" ]; then
    case "$LOG_INTERNAL_DEBUG_FILE" in
      */*)
        log__dir=${LOG_INTERNAL_DEBUG_FILE%/*}
        [ -d "$log__dir" ] || mkdir -p "$log__dir" || return 1
        ;;
    esac
    printf '%s\n' "$log__line" >>"$LOG_INTERNAL_DEBUG_FILE" 2>/dev/null || return 1
  else
    printf '%s\n' "$log__line" >&2
  fi
}

log__dbg "log.sh loaded: pid=$$ LOG_HELPER_DIR=$log__helper_dir"

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

log__safe_job_name() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'
}

log__normalize_level() {
  log__raw=${1:-INFO}

  case "$log__raw" in
    INFO|WARN|ERR|DEBUG|OUT|DBG)
      printf '%s' "$log__raw"
      ;;
    *)
      printf '%s' "$log__raw" | tr '[:lower:]' '[:upper:]'
      ;;
  esac
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
  log__log_file=$1
  log__job=${2:-${LOG_JOB_NAME:-log}}
  log__safe=$(log__safe_job_name "$log__job")

  case "$log__log_file" in
    */*) log__base=${log__log_file%/*} ;;
    *)   log__base=. ;;
  esac

  printf '%s/%s-latest.log' "$log__base" "$log__safe"
}

# ------------------------------------------------------------------------------
# File append
# ------------------------------------------------------------------------------

log__append_file() {
  log__line=$1
  [ -n "${LOG_FILE:-}" ] || return 0

  case "${LOG_FILE}" in
    */*)
      log__dir=${LOG_FILE%/*}
      [ -d "$log__dir" ] || mkdir -p "$log__dir" 2>/dev/null || return 1
      ;;
  esac

  printf '%s\n' "$log__line" >>"$LOG_FILE" 2>/dev/null || {
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
    LOG_RUN_TS=$(log__now_utc_runid 2>/dev/null || printf run)
  fi

  log__safe=$(log__safe_job_name "$LOG_JOB_NAME")

  if [ -z "${LOG_FILE:-}" ]; then
    log__dir=$(log__default_log_dir "$log__safe")
    LOG_FILE="$log__dir/$log__safe-$LOG_RUN_TS.log"
  fi

  case "${LOG_FILE}" in
    */*)
      log__dir_path=${LOG_FILE%/*}
      if [ ! -d "$log__dir_path" ]; then
        mkdir -p "$log__dir_path" 2>/dev/null || return 1
      fi
      ;;
  esac

  : >"$LOG_FILE" 2>/dev/null || return 1

  LOG_LATEST_LINK=${LOG_LATEST_LINK:-$(log__latest_link_path "$LOG_FILE" "$log__safe")}

  export LOG_FILE LOG_JOB_NAME LOG_RUN_TS LOG_LATEST_LINK LOG_ROOT LOG_ROLLING_VAULT_ROOT

  log_info "log_init: opened LOG_FILE=$LOG_FILE" || return 1

  LOG_INIT_DONE=1
}

# Canonical lifecycle entry point (manual lifecycle: start -> work -> finish)
log_start_job() {
  log__job=$1
  shift || true

  LOG_JOB_NAME=$(log__safe_job_name "$log__job")
  LOG_RUN_START_SEC=$(log__now_utc_epoch 2>/dev/null || printf '')
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
  log__segment=$1
  log__cleaned=$(printf '%s' "$log__segment" | tr '-' ' ')
  printf '%s' "$log__cleaned" |
    awk '{ for (i = 1; i <= NF; i++) { $i = toupper(substr($i,1,1)) substr($i,2) } printf "%s", $0 }'
}

log__rolling_note_path() {
  [ -n "${LOG_ROLLING_VAULT_ROOT:-}" ] || return 1

  log__log_file=${1:-${LOG_FILE:-}}
  [ -n "$log__log_file" ] || return 1

  log__safe_job=$(log__safe_job_name "${LOG_JOB_NAME:-}")

  if [ -z "$log__safe_job" ]; then
    log__base_name=${log__log_file##*/}
    log__base_trimmed=${log__base_name%.log}
    log__safe_job=$(log__safe_job_name "${log__base_trimmed%-*}")
  fi

  [ -n "$log__safe_job" ] || log__safe_job=log

  log__mapped_root="${LOG_ROLLING_VAULT_ROOT%/}/Server Logs"

  case "$log__log_file" in
    */logs/*) log__rel_path=${log__log_file#*/logs/} ;;
    *)        log__rel_path=${log__log_file##*/} ;;
  esac

  case "$log__rel_path" in
    */*) log__rel_dir=${log__rel_path%/*} ;;
    *)   log__rel_dir= ;;
  esac

  log__mapped_dir=$log__mapped_root

  if [ -n "$log__rel_dir" ]; then
    log__old_ifs=$IFS
    IFS='/'
    set -- $log__rel_dir
    IFS=$log__old_ifs

    for log__segment in "$@"; do
      log__formatted=$(log__format_dir_segment "$log__segment")
      log__mapped_dir="$log__mapped_dir/$log__formatted"
    done
  fi

  printf '%s/%s-latest.md' "$log__mapped_dir" "$log__safe_job"
}

log_update_rolling_note() {
  [ -n "${LOG_ROLLING_VAULT_ROOT:-}" ] || return 0

  log__log_file=${LOG_FILE:-}
  [ -n "$log__log_file" ] || return 0

  log__rolling_path=$(log__rolling_note_path "$log__log_file") || return 0
  [ -n "$log__rolling_path" ] || return 0

  case "$log__rolling_path" in
    */*)
      log__rolling_dir=${log__rolling_path%/*}
      if [ ! -d "$log__rolling_dir" ]; then
        mkdir -p "$log__rolling_dir" 2>/dev/null || return 1
      fi
      ;;
  esac

  log__tmp_path="${log__rolling_path}.tmp"

  log__ts=$(log__now_local_iso 2>/dev/null || printf 'unknown')
  log__job_title=${LOG_JOB_NAME:-Latest Log}

  log__dbg "rolling_note: from=$log__log_file to=$log__rolling_path"

  if ! {
    printf '# %s\n\n' "$log__job_title"
    printf 'Source: `%s`\n' "$log__log_file"
    printf 'Timestamp: %s\n\n' "$log__ts"
    printf '```text\n'
    if [ -n "${LOG_ROLLING_LINES:-}" ]; then
      if ! tail -n "$LOG_ROLLING_LINES" "$log__log_file" 2>/dev/null; then
        tail -"$LOG_ROLLING_LINES" "$log__log_file" 2>/dev/null || return 1
      fi
    else
      cat "$log__log_file" || return 1
    fi
    printf '\n```\n'
  } >"$log__tmp_path"; then
    return 1
  fi

  mv "$log__tmp_path" "$log__rolling_path" || return 1
}

log_rotate() {
  log__keep_arg=${1:-}
  log__keep=${log__keep_arg:-${LOG_KEEP:-20}}
  log__log_file=${LOG_FILE:-}
  log__job_name=${LOG_JOB_NAME:-}

  [ -n "$log__log_file" ] || return 0

  case "$log__log_file" in
    */*) log__log_dir=${log__log_file%/*} ;;
    *)   return 0 ;;
  esac

  if [ -z "$log__job_name" ]; then
    log__base_name=${log__log_file##*/}
    log__job_name=${log__base_name%-*}
  fi

  log__safe_job=$(log__safe_job_name "$log__job_name")

  set -- "$log__log_dir"/${log__safe_job}-*.log

  if [ $# -eq 1 ] && [ "$1" = "$log__log_dir/${log__safe_job}-"*.log ]; then
    return 0
  fi

  if ! log__old_list=$(ls -1t "$@" 2>/dev/null | awk -v n="$log__keep" 'NR>n'); then
    return 1
  fi

  [ -n "${log__old_list:-}" ] || return 0

  log__old_IFS=$IFS
  IFS=$(printf '\n')
  set -- $log__old_list
  IFS=$log__old_IFS

  for log__old_log in "$@"; do
    [ -n "$log__old_log" ] || continue
    rm -f -- "$log__old_log" || return 1
  done
}

log_update_latest_link() {
  log__log_file=${LOG_FILE:-}
  log__link_path=${LOG_LATEST_LINK:-}

  if [ -z "$log__log_file" ] || [ -z "$log__link_path" ]; then
    return 0
  fi

  case "$log__link_path" in
    */*)
      log__link_dir=${log__link_path%/*}
      if [ -n "$log__link_dir" ] && [ ! -d "$log__link_dir" ]; then
        mkdir -p "$log__link_dir" 2>/dev/null || return 1
      fi
      ;;
  esac

  log__target_path=$log__log_file
  if [ "${LOG_LATEST_RELATIVE:-1}" -ne 0 ]; then
    case "$log__log_file" in
      */*) log__log_dir=${log__log_file%/*} ;;
      *)   log__log_dir="." ;;
    esac

    case "$log__link_path" in
      */*) log__link_dir=${log__link_path%/*} ;;
      *)   log__link_dir="." ;;
    esac

    if [ "$log__log_dir" = "$log__link_dir" ]; then
      log__target_path=$(basename "$log__log_file")
    fi
  fi

  ln -sf "$log__target_path" "$log__link_path" 2>/dev/null || return 1
}

# ------------------------------------------------------------------------------
# Finish
# ------------------------------------------------------------------------------

log_finish_job() {
  log__status=$1

  log__end_ts=$(log__now_utc_runid 2>/dev/null || printf unknown)

  log_info "------------------------------"
  log_info "exit=$log__status"
  log_info "utc_end=$log__end_ts"
  log_info "== ${LOG_JOB_NAME} end =="

  log_update_latest_link || return 1
  log_rotate || return 1
  log_update_rolling_note || return 1

  return "$log__status"
}

log_stream_file() {
  log__capture_level=${LOG_CAPTURE_LEVEL:-OUT}
  log__capture_stream=${LOG_CAPTURE_STREAM:-stderr}

  while IFS= read -r log__line || [ -n "$log__line" ]; do
    log__emit "$log__capture_level" "$log__capture_stream" "$log__line"
  done <"$1"
}

log_run_with_capture() {
  log__tmp=$(mktemp 2>/dev/null || mktemp "/tmp/log.${LOG_JOB_NAME:-job}.XXXXXX") || {
    log_err "mktemp failed"
    return 127
  }

  set +e
  "$@" >"$log__tmp" 2>&1
  log__status=$?
  set -e

  log_stream_file "$log__tmp"
  rm -f "$log__tmp"

  return "$log__status"
}

log__quote_args() {
  while [ $# -gt 0 ]; do
    log__escaped=$(printf "%s" "$1" | sed "s/'/'\\\\''/g")
    printf " '%s'" "$log__escaped"
    shift
  done
}

# Compatibility wrapper: wrapped lifecycle (start -> run command -> finish)
# Delegates to log_start_job to keep lifecycle logging canonical.
log_run_job() {
  log__job_name=${1:-}
  shift

  [ -n "$log__job_name" ] || {
    log_err "log_run_job: missing job name"
    return 2
  }

  log__meta_args=
  while [ $# -gt 0 ]; do
    case "$1" in
      --)
        shift
        break
        ;;
      *)
        log__escaped=$(printf "%s" "$1" | sed "s/'/'\\\\''/g")
        log__meta_args="$log__meta_args '$log__escaped'"
        shift
        ;;
    esac
  done

  if [ $# -eq 0 ]; then
    log_err "log_run_job: missing command to run"
    return 2
  fi

  log__cmd_args=$(log__quote_args "$@")

  if [ -n "$log__meta_args" ]; then
    eval "set --$log__meta_args"
  else
    set --
  fi

  log_start_job "$log__job_name" "$@"

  eval "set --$log__cmd_args"

  log_run_with_capture "$@"
  log__status=$?

  log_finish_job "$log__status"

  return "$log__status"
}

# ------------------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------------------

# Log line contract:
# - Structure: "<timestamp> <LEVEL> <message>" where timestamp is ISO-8601. When
#   LOG_TIMESTAMP=0 or a timestamp cannot be produced, the timestamp field is a
#   literal "-" to keep the structure stable for parsers.
# - LEVEL is always an explicit token (INFO, WARN, ERR, DEBUG, OUT, DBG) and is
#   never inferred from the message text.
# - Message text is sanitized (ASCII-only when LOG_ASCII_ONLY!=0).
# Examples:
#   2025-01-02T03:04:05+0000 INFO == job start ==
#   2025-01-02T03:04:06+0000 INFO utc_start=20250102T030405Z
#   - INFO LOG_TIMESTAMP disabled; using placeholder timestamp field
#   2025-01-02T03:05:00+0000 WARN retrying fetch (attempt=2)
#   2025-01-02T03:05:01+0000 WARN disk space below threshold
#   - WARN degraded mode enabled by operator
#   2025-01-02T03:06:00+0000 ERR download failed (status=503)
#   2025-01-02T03:06:05+0000 ERR cannot write output directory
#   - ERR final attempt exhausted
#   2025-01-02T03:07:00+0000 DEBUG captured payload length=42
#   2025-01-02T03:07:01+0000 DEBUG env flag LOG_DEBUG=1
#   - DEBUG tracing enabled without timestamp field

log__emit() {
  log__level=$(log__normalize_level "$1")
  log__stream=$2
  shift 2
  log__msg=$(log__sanitize "$*")

  log__line=$(log__format_line "$log__level" "$log__msg")

  case "$log__stream" in
    stderr) printf '%s\n' "$log__line" >&2 ;;
    *)      printf '%s\n' "$log__line" ;;
  esac

  log__append_file "$log__line" || return 1
}

log_info()  { log__emit INFO  "${LOG_INFO_STREAM:-stderr}" "$@"; }
log_warn()  { log__emit WARN  stderr "$@"; }
log_err()   { log__emit ERR   stderr "$@"; }
log_debug() {
  [ "${LOG_DEBUG:-0}" -ne 0 ] && log__emit DEBUG "${LOG_DEBUG_STREAM:-stderr}" "$@"
}
