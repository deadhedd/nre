#!/bin/sh
# utils/core/job-wrap.sh
# Execution wrapper + logging authority bootstrap.
# Wrapper diagnostics use the same level-prefix scheme as leaf scripts.
# Author: deadhedd
# License: MIT
# shellcheck shell=sh

###############################################################################
# Contract-aligned wrapper exit codes (Appendix C)
# 120 invocation misuse
# 121 wrapper init failure
# 122 hard logging / blocked required publication
# 123 commit helper failure
# 124 internal invariant / unexpected wrapper failure
###############################################################################
WRAP_E_INVOCATION=120
WRAP_E_INIT=121
WRAP_E_LOGGING=122
WRAP_E_COMMIT=123
WRAP_E_INTERNAL=124

###############################################################################
# Minimal, cron-safe PATH (contract: explicit baseline PATH)
###############################################################################
PATH=/usr/local/bin:/usr/bin:/bin${PATH+:$PATH}
export PATH

###############################################################################
# wrapper state (initialize early so wrapper diagnostics behave correctly)
###############################################################################
LOG_DEGRADED=1      # 1 => file-backed logging degraded/unavailable (soft)
WRAP_UNSAFE=0       # reserved for future unsafe execution context detection
CAPTURE_MODE=file   # file | passthrough

# Wrapper-owned bootstrap diagnostics (best-effort, may remain empty)
WRAP_BOOT_LOG=""

# Optional commit orchestration (wrapper-owned)
COMMIT_MODE=${COMMIT_MODE:-best-effort}   # off | best-effort | required
COMMIT_LIST_FILE=""
COMMIT_MESSAGE=${COMMIT_MESSAGE:-""}

# Wrapper debug knob (opt-in; boundary stderr noise)
JOB_WRAP_DEBUG=${JOB_WRAP_DEBUG:-0}
export JOB_WRAP_DEBUG

# Reliable newline sentinel for POSIX sh pattern matching
_NL=$(printf '\n')

###############################################################################
# Wrapper diagnostics helper (wrapper never writes stdout)
#
# Intention:
# - Single level-gating policy via LOG_MIN_LEVEL, regardless of degraded/healthy.
# - Healthy: use centralized logging; boundary stderr is quiet except WARN/ERROR
#           (or everything when JOB_WRAP_DEBUG=1).
# - Degraded: use internal fallback (bootstrap + boundary), same level gating.
# - This fallback is NOT a second logging system: no pruning/latest/per-run logs.
###############################################################################
_wrap_level_num() {
  case "$1" in
    DEBUG) printf '%s\n' 10 ;;
    INFO)  printf '%s\n' 20 ;;
    WARN)  printf '%s\n' 30 ;;
    ERROR) printf '%s\n' 40 ;;
    *)     printf '%s\n' 0 ;;
  esac
}

_wrap_level_ok() {
  _ln=$(_wrap_level_num "$1")
  _mn=$(_wrap_level_num "${LOG_MIN_LEVEL:-INFO}")
  [ "$_ln" -ge "$_mn" ]
}

_wrap_emit() {
  _lvl=$1
  shift
  _msg=$*

  case "$_lvl" in
    DEBUG|INFO|WARN|ERROR) : ;;
    *) _lvl=ERROR ;;
  esac

  # Apply the same level gating regardless of degraded/healthy.
  if ! _wrap_level_ok "$_lvl"; then
    return 0
  fi

  # Boundary visibility rules:
  # - Degraded: eligible wrapper diagnostics go to boundary stderr (single-line)
  # - Healthy: only WARN/ERROR go to boundary stderr unless JOB_WRAP_DEBUG=1
  _emit_boundary=0
  if [ "${LOG_DEGRADED:-1}" -eq 1 ]; then
    _emit_boundary=1
  else
    case "$_lvl" in
      WARN|ERROR) _emit_boundary=1 ;;
      *) [ "${JOB_WRAP_DEBUG:-0}" = "1" ] && _emit_boundary=1 ;;
    esac
  fi

  # If multiline, keep boundary clean (single line) but preserve full evidence.
  case "$_msg" in
    *"$_NL"*)
      if [ -n "${WRAP_BOOT_LOG:-}" ]; then
        {
          printf '%s: WRAP: (multiline diagnostic; full text follows)\n' "$_lvl"
          printf '%s\n' "$_msg"
        } >>"$WRAP_BOOT_LOG" 2>/dev/null || :
      fi

      if [ "$_emit_boundary" -eq 1 ]; then
        printf '%s: WRAP: multiline diagnostic (see bootstrap: %s)\n' \
          "$_lvl" "${WRAP_BOOT_LOG:-<unavailable>}" >&2
      fi
      return 0
      ;;
  esac

  # Boundary visibility (single line) — gated as described above.
  if [ "$_emit_boundary" -eq 1 ]; then
    printf '%s: WRAP: %s\n' "$_lvl" "$_msg" >&2
  fi

  # Best-effort persistence for wrapper diagnostics (single line).
  # When degraded, bootstrap is the internal fallback persistence channel.
  if [ -n "${WRAP_BOOT_LOG:-}" ]; then
    printf '%s: WRAP: %s\n' "$_lvl" "$_msg" >>"$WRAP_BOOT_LOG" 2>/dev/null || :
  fi

  # If logging is active and not degraded, also write into the per-run log.
  # Best-effort only: MUST NOT affect wrapper behavior.
  if [ "${LOG_DEGRADED:-1}" -eq 0 ] && [ -n "${LOG_FILE:-}" ]; then
    case "$_lvl" in
      DEBUG) log_debug "WRAP: $_msg" >/dev/null 2>&1 || : ;;
      INFO)  log_info  "WRAP: $_msg" >/dev/null 2>&1 || : ;;
      WARN)  log_warn  "WRAP: $_msg" >/dev/null 2>&1 || : ;;
      *)     log_error "WRAP: $_msg" >/dev/null 2>&1 || : ;;
    esac
  fi
}

_wrap_debug() { _wrap_emit DEBUG "$@"; }
_wrap_info()  { _wrap_emit INFO  "$@"; }
_wrap_warn()  { _wrap_emit WARN  "$@"; }
_wrap_error() { _wrap_emit ERROR "$@"; }

###############################################################################
# wrapper guard (prevent double-wrap loops)
###############################################################################
if [ "${JOB_WRAP_ACTIVE:-}" = "1" ]; then
  _wrap_error "job-wrap.sh invoked while already active (JOB_WRAP_ACTIVE=1)"
  exit "$WRAP_E_INVOCATION"
fi
JOB_WRAP_ACTIVE=1
export JOB_WRAP_ACTIVE

###############################################################################
# usage
###############################################################################
if [ $# -lt 1 ]; then
  _wrap_error "usage: job-wrap.sh <leaf-script> [args...]"
  exit "$WRAP_E_INVOCATION"
fi

LEAF_PATH=$1
shift

###############################################################################
# locate wrapper dir + repo root (STRUCTURAL, NOT HEURISTIC)
###############################################################################
WRAP_DIR=$(cd "$(dirname "$0")" && pwd -P) || {
  _wrap_error "cannot resolve wrapper directory"
  exit "$WRAP_E_INIT"
}

REPO_ROOT=$(cd "$WRAP_DIR/.." && pwd -P) || {
  _wrap_error "cannot resolve repo root from rebuild layout"
  exit "$WRAP_E_INIT"
}

###############################################################################
# logging lib wiring (contract: wrapper must provide LOG_LIB_DIR)
###############################################################################
LOG_LIB_DIR=${LOG_LIB_DIR:-$WRAP_DIR}
export LOG_LIB_DIR

# shellcheck disable=SC1090
. "$LOG_LIB_DIR/log.sh" || {
  _wrap_error "cannot source log facade: $LOG_LIB_DIR/log.sh"
  exit "$WRAP_E_INIT"
}

###############################################################################
# derive JOB_NAME (strict: must already be safe for sink)
###############################################################################
_job_base=$(basename "$LEAF_PATH")
JOB_NAME=${_job_base%.sh}
export JOB_NAME

case "$JOB_NAME" in
  ""|"."|"..")
    _wrap_error "invalid JOB_NAME derived from leaf: $JOB_NAME"
    exit "$WRAP_E_INVOCATION"
    ;;
  esac

case "$JOB_NAME" in
  *[!A-Za-z0-9._-]*)
    _wrap_error "invalid JOB_NAME (allowed: [A-Za-z0-9._-]): $JOB_NAME"
    exit "$WRAP_E_INVOCATION"
    ;;
esac

###############################################################################
# logger inputs
###############################################################################
LOG_ROOT=${LOG_ROOT:-"$REPO_ROOT/logs"}
LOG_BUCKET=${LOG_BUCKET:-other}
LOG_KEEP_COUNT=${LOG_KEEP_COUNT:-0}
LOG_MIN_LEVEL=${LOG_MIN_LEVEL:-INFO}

export LOG_ROOT LOG_BUCKET LOG_KEEP_COUNT LOG_MIN_LEVEL

###############################################################################
# wrapper bootstrap diagnostics
###############################################################################
_boot_dir="${LOG_ROOT}/_bootstrap"
_boot_ts=$(LC_ALL=C date '+%Y-%m-%d-%H%M%S' 2>/dev/null || printf 'unknown-ts')
WRAP_BOOT_LOG="${_boot_dir}/${JOB_NAME}-bootstrap-${_boot_ts}-$$.log"

mkdir -p "$_boot_dir" 2>/dev/null || WRAP_BOOT_LOG=""
: >>"$WRAP_BOOT_LOG" 2>/dev/null || WRAP_BOOT_LOG=""

if [ -n "$WRAP_BOOT_LOG" ]; then
  _wrap_debug "bootstrap diagnostics active: $WRAP_BOOT_LOG"
else
  _wrap_warn "bootstrap diagnostics unavailable (cannot write under LOG_ROOT)"
fi

###############################################################################
# commit wiring (wrapper-owned)
###############################################################################
export COMMIT_MODE

COMMIT_LIST_FILE="${TMPDIR:-/tmp}/jobwrap.commitlist.${JOB_NAME}.$$"
export COMMIT_LIST_FILE
: >"$COMMIT_LIST_FILE" 2>/dev/null || COMMIT_LIST_FILE=""

if [ -z "${COMMIT_MESSAGE:-}" ]; then
  _cm_ts=$(LC_ALL=C date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf 'unknown-time')
  COMMIT_MESSAGE="auto: ${JOB_NAME} @ ${_cm_ts} (local)"
fi
export COMMIT_MESSAGE

###############################################################################
# init logger
###############################################################################
_init_out="${TMPDIR:-/tmp}/jobwrap.init.out.${JOB_NAME}.$$"
_init_err="${TMPDIR:-/tmp}/jobwrap.init.err.${JOB_NAME}.$$"
rm -f "$_init_out" "$_init_err" 2>/dev/null || :
: >"$_init_out" 2>/dev/null || _init_out=/dev/null
: >"$_init_err" 2>/dev/null || _init_err=/dev/null

log_init "$JOB_NAME" "$LOG_MIN_LEVEL" >"$_init_out" 2>"$_init_err"
_lrc=$?

# Sticky flag: if log_init leaked stdout, logging MUST remain degraded.
_init_leaked_stdout=0
if [ -s "$_init_out" ]; then
  _init_leaked_stdout=1
  LOG_DEGRADED=1
  if [ -n "${WRAP_BOOT_LOG:-}" ]; then
    {
      printf 'BOOTSTRAP WARN: contract violation contained: log_init wrote to stdout\n'
      printf '--- leaked stdout ---\n'
      cat "$_init_out" 2>/dev/null || :
      printf '\n--- stderr ---\n'
      cat "$_init_err" 2>/dev/null || :
    } >>"$WRAP_BOOT_LOG" 2>/dev/null || :
  fi
  _wrap_warn "CONTRACT VIOLATION (contained): log_init wrote to stdout; proceeding with stderr-only logging"
fi

case "$_lrc" in
  0)  LOG_DEGRADED=0 ;;
  10) LOG_DEGRADED=1; _wrap_warn "logger init operational failure; stderr-only logging" ;;
  11) _wrap_error "logger init misuse; aborting"; exit "$WRAP_E_INIT" ;;
  *)  LOG_DEGRADED=1; _wrap_warn "logger init failed; stderr-only logging" ;;
esac

# Enforce contract: stdout leak => degraded, regardless of log_init rc.
if [ "$_init_leaked_stdout" -eq 1 ]; then
  LOG_DEGRADED=1
fi

###############################################################################
# capture leaf stderr
###############################################################################
_tmp="${TMPDIR:-/tmp}/jobwrap.${JOB_NAME}.$$"
rm -f "$_tmp" 2>/dev/null || :

: >"$_tmp" 2>/dev/null || { CAPTURE_MODE=passthrough; LOG_DEGRADED=1; }

_cleanup() {
  rm -f "$_tmp" "$_init_out" "$_init_err" "$_lc_err" "$COMMIT_LIST_FILE" 2>/dev/null || :
}
trap _cleanup EXIT HUP INT TERM

if [ "$CAPTURE_MODE" = "file" ]; then
  "$LEAF_PATH" "$@" 2>"$_tmp"
  _leaf_rc=$?
else
  # passthrough mode: leaf stderr reaches boundary verbatim by design
  "$LEAF_PATH" "$@"
  _leaf_rc=$?
fi

###############################################################################
# route leaf stderr
###############################################################################
if [ "$CAPTURE_MODE" = "file" ] && [ -s "$_tmp" ]; then
  if [ "$LOG_DEGRADED" -eq 0 ]; then
    _lc_err="${TMPDIR:-/tmp}/jobwrap.capture.err.${JOB_NAME}.$$"
    rm -f "$_lc_err" 2>/dev/null || :
    : >"$_lc_err" 2>/dev/null || _lc_err=/dev/null

    log_capture ERROR <"$_tmp" >/dev/null 2>"$_lc_err"
    _lc_rc=$?

    if [ "$_lc_rc" -ne 0 ]; then
      LOG_DEGRADED=1
      _wrap_warn "log_capture failed; centralized logging degraded (replaying leaf stderr to boundary)"

      if [ -n "${WRAP_BOOT_LOG:-}" ]; then
        {
          printf 'BOOTSTRAP WARN: log_capture failure\n'
          printf 'log_capture exit=%s\n' "$_lc_rc"
          printf '--- log_capture stderr ---\n'
          cat "$_lc_err" 2>/dev/null || :
          printf '\n--- captured leaf stderr (replayed to boundary) ---\n'
          cat "$_tmp" 2>/dev/null || :
        } >>"$WRAP_BOOT_LOG" 2>/dev/null || :
      fi

      # Option A: fail-open visibility
      cat "$_tmp" >&2 2>/dev/null || :
    fi
  fi
fi

###############################################################################
# Optional commit orchestration
###############################################################################
_commit_attempted=0
_commit_rc=0

if [ "$COMMIT_MODE" != "off" ] && [ "$_leaf_rc" -eq 0 ] && [ -s "$COMMIT_LIST_FILE" ]; then
  _commit_attempted=1
  _commit_helper="$LOG_LIB_DIR/commit.sh"

  set --
  while IFS= read -r _line; do
    case "$_line" in ""|\#*) continue ;; esac
    set -- "$@" "$_line"
  done <"$COMMIT_LIST_FILE"

  "$_commit_helper" "$REPO_ROOT" "$COMMIT_MESSAGE" "$@"
  _commit_rc=$?

  # Contract-aligned:
  # In best-effort and required, a commit failure outcome is an engine failure
  # when a commit was attempted. Treat 0 and 3 ("no changes") as non-failure.
  case "$_commit_rc" in
    0|3) : ;;
    *)
      _wrap_error "commit helper failed (mode=$COMMIT_MODE rc=$_commit_rc); overriding leaf exit"
      exit "$WRAP_E_COMMIT"
      ;;
  esac
fi

###############################################################################
# finalization
###############################################################################
exit "$_leaf_rc"
