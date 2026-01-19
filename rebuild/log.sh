#!/bin/sh
# rebuild/log.sh
# Logging facade and coordinator (library-only; wrapper-only).
# Author: deadhedd
# License: MIT
# shellcheck shell=sh

###############################################################################
# guard: library-only (MUST be sourced)
###############################################################################
if (return 0 2>/dev/null); then
  : # sourced, OK
else
  echo "ERROR: log.sh is a library and must be sourced, not executed" >&2
  exit 2
fi

case "${LOG_FACADE_ACTIVE:-0}" in
  1) return 0 ;;
esac
LOG_FACADE_ACTIVE=1

###############################################################################
# internal state (must be safe under set -eu callers)
###############################################################################
_log_sink_ready=0

###############################################################################
# internal helpers (NEVER stdout)
###############################################################################
_log_err() {
  # single-line-ish: strip control chars to avoid accidental multi-line
  _log_m=$*
  _log_m=$(printf '%s' "$_log_m" | LC_ALL=C tr -d '[:cntrl:]')
  printf 'LOG: %s\n' "$_log_m" >&2
}

_log_require_wrapper() {
  if [ "${JOB_WRAP_ACTIVE:-}" != "1" ]; then
    _log_err "misuse: invoked without wrapper context (JOB_WRAP_ACTIVE!=1)"
    return 11
  fi
  return 0
}

_log_require_nonempty() {
  # Args: $1=var_name, $2=value
  _log_vname=${1:-}
  _log_vval=${2-}
  if [ -z "${_log_vval:-}" ]; then
    _log_err "misuse: required ${_log_vname} is empty"
    return 11
  fi
  return 0
}

_log_resolve_lib_dir() {
  # Resolve wrapper-provided logger library directory.
  #
  # Contract intent:
  # - log.sh cannot portably discover its own path when sourced (POSIX sh).
  # - Wrapper (job-wrap.sh) should provide LOG_LIB_DIR (internal wiring var).
  #
  # Accepted vars (first match wins):
  #   LOG_LIB_DIR      (preferred)
  #   log_lib_dir      (compat / transitional)
  #
  # Returns:
  #   0  and sets _log_lib_dir
  #   11 on misuse / invalid value
  _log_lib_dir=${LOG_LIB_DIR:-${log_lib_dir:-}}

  if [ -z "${_log_lib_dir:-}" ]; then
    _log_err "misuse: LOG_LIB_DIR is required to source logger children"
    return 11
  fi

  # Must be an existing directory.
  if [ ! -d "${_log_lib_dir}" ]; then
    _log_err "misuse: LOG_LIB_DIR is not a directory: ${_log_lib_dir}"
    return 11
  fi

  # Normalize to an absolute, physical path.
  _log_lib_dir=$(cd "${_log_lib_dir}" && pwd -P) || {
    _log_err "operational failure: cannot resolve LOG_LIB_DIR: ${_log_lib_dir}"
    return 10
  }

  return 0
}

_log_source_children() {
  # Source helpers relative to wrapper-provided LOG_LIB_DIR (repo-stable).
  _log_resolve_lib_dir || return $?

  # Redirect any accidental stdout during sourcing to stderr to preserve
  # "stdout is sacred" while retaining visibility.
  # shellcheck disable=SC1090
  . "${_log_lib_dir}/datetime.sh"    1>&2 || return 10
  # shellcheck disable=SC1090
  . "${_log_lib_dir}/log-format.sh"  1>&2 || return 10
  # shellcheck disable=SC1090
  . "${_log_lib_dir}/log-sink.sh"    1>&2 || return 10
  # shellcheck disable=SC1090
  . "${_log_lib_dir}/log-capture.sh" 1>&2 || return 10

  return 0
}

_log_write_line() {
  # Writes an already-formatted single line (no trailing newline) to the active sink.
  # Args: $1 = line
  if [ "${_log_sink_ready:-0}" = "1" ]; then
    # log-sink's internal writer adds newline.
    _ls_write_line "$1" 1>/dev/null
    return $?
  fi

  # stderr-only degradation (still never stdout)
  printf '%s\n' "$1" >&2
  return 0
}

_log_format_and_write() {
  # Args: $1=LEVEL, $2=message
  _log_lvl=${1:-}
  _log_msg=${2-}

  _log_out=""
  # Prevent any formatter stdout from leaking toward job stdout even if formatter is buggy.
  log_format_build_line _log_out "${LOG_MIN_LEVEL:-}" "${_log_lvl}" "${_log_msg}" 1>/dev/null
  _log_rc=$?

  case "$_log_rc" in
    0) _log_write_line "${_log_out}" ; return $? ;;
    4) return 4 ;;              # suppressed by policy (non-failure)
    10|11) return "$_log_rc" ;;  # propagate helper semantics
    *) _log_err "operational failure: unexpected formatter rc=$_log_rc" ; return 10 ;;
  esac
}

###############################################################################
# public API (for job-wrap.sh)
###############################################################################

log_init() {
  # Usage:
  #   log_init <JOB_NAME> <LOG_FILE> [MIN_LEVEL]
  #
  # - Requires wrapper context (JOB_WRAP_ACTIVE=1)
  # - Establishes facade ownership (LOG_FACADE_ACTIVE=1)
  # - Sources child helpers
  # - Initializes sink (FD 3) or degrades to stderr-only
  #
  # Returns:
  #   0  success (sink ready) OR success w/ stderr-only already active
  #   4  suppressed by policy (non-failure; should not occur for init path)
  #   10 operational failure (e.g., cannot source/init helpers) [caller may treat soft]
  #   11 misuse (e.g., not in wrapper context; missing/invalid JOB_NAME/LOG_FILE/LOG_LIB_DIR;
  #              invalid LOG_MIN_LEVEL; other facade-context misuse)

  _log_require_wrapper || return $?

  # Establish facade ownership BEFORE any helper is invoked.
  LOG_FACADE_ACTIVE=1

  # Define facade context vars early (safe for set -u callers).
  JOB_NAME=${1:-}
  LOG_FILE=${2:-}
  LOG_MIN_LEVEL=${3:-INFO}

  # --------------------------------------------------------------------------
  # Phase 1: facade-level misuse validation (NO helper sourcing yet)
  # --------------------------------------------------------------------------
  _log_require_nonempty "JOB_NAME" "${JOB_NAME:-}" || {
    _log_sink_ready=0
    LOG_SINK_FD=2
    return 11
  }
  _log_require_nonempty "LOG_FILE" "${LOG_FILE:-}" || {
    _log_sink_ready=0
    LOG_SINK_FD=2
    return 11
  }

  # Validate LOG_FILE basename matches: <JOB>-YYYY-MM-DD-HHMMSS.log
  # (This prevents sink/FS work from masking misuse as rc=10.)
  _log_base=$(basename "${LOG_FILE}" 2>/dev/null || printf '%s' "${LOG_FILE}")
  case "${_log_base}" in
    "${JOB_NAME}"-????-??-??-??????.log) : ;;
    *)
      _log_err "misuse: invalid LOG_FILE basename (expected ${JOB_NAME}-YYYY-MM-DD-HHMMSS.log): ${_log_base}"
      _log_sink_ready=0
      LOG_SINK_FD=2
      return 11
      ;;
  esac

  # --------------------------------------------------------------------------
  # FIX: facade-level MIN_LEVEL validation (NO formatter probing)
  # --------------------------------------------------------------------------
  case "$LOG_MIN_LEVEL" in
    DEBUG|INFO|WARN|ERROR) : ;;
    *)
      _log_err "misuse: invalid LOG_MIN_LEVEL=${LOG_MIN_LEVEL} (expected DEBUG|INFO|WARN|ERROR)"
      _log_sink_ready=0
      LOG_SINK_FD=2
      return 11
      ;;
  esac

  # --------------------------------------------------------------------------
  # Phase 2: operational setup (source helpers)
  # --------------------------------------------------------------------------
  _log_source_children || {
    _log_rc=$?
    _log_err "operational failure: cannot source logger children (rc=$_log_rc)"
    _log_sink_ready=0
    LOG_SINK_FD=2
    return 10
  }

  # Initialize sink. On success, sink opens FD 3 and _ls_write_line writes to it.
  log_sink_init 1>/dev/null
  _log_src=$?

  if [ "$_log_src" -eq 0 ]; then
    _log_sink_ready=1
    LOG_SINK_FD=3
    return 0
  fi

  # Degrade to stderr-only but return the sink rc so the wrapper can decide escalation.
  _log_sink_ready=0
  LOG_SINK_FD=2
  _log_err "sink init failed (rc=$_log_src); degrading to stderr-only logging"
  return "$_log_src"
}

log_close() {
  # Best-effort shutdown. Never stdout.
  if [ "${LOG_FACADE_ACTIVE:-}" != "1" ]; then
    _log_err "misuse: log_close invoked without facade ownership (LOG_FACADE_ACTIVE!=1)"
    return 11
  fi

  if [ "${_log_sink_ready:-0}" = "1" ]; then
    log_sink_close 1>/dev/null || :
  fi

  _log_sink_ready=0
  LOG_SINK_FD=2
  return 0
}

log_debug() { _log_format_and_write DEBUG "${*}"; }
log_info()  { _log_format_and_write INFO  "${*}"; }
log_warn()  { _log_format_and_write WARN  "${*}"; }
log_error() { _log_format_and_write ERROR "${*}"; }

log_capture() {
  # Capture stdin as log lines at a given LEVEL.
  # Usage:
  #   some_cmd 2>&1 | log_capture INFO
  #
  # Returns helper codes: 0,4,10,11
  _log_lvl=${1:-}
  log_capture_stream "${_log_lvl}"
  return $?
}
