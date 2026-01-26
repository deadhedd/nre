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
# 123 commit helper failure (when commit required/best-effort attempted)
###############################################################################

WRAP_E_INVOCATION=120
WRAP_E_INIT=121
WRAP_E_COMMIT=123

###############################################################################
# Internal state
###############################################################################

JOB_WRAP_ACTIVE=${JOB_WRAP_ACTIVE:-0}
LOG_DEGRADED=1
WRAP_BOOT_LOG=""
CAPTURE_MODE="file"

# Wrapper "level prefix" newline for multiline detection
_NL=$(printf '\n')

###############################################################################
# Level helpers (small, local)
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

  _wrap_level_ok "$_lvl" || return 0

  # Default boundary emission rules:
  # - If degraded: allow DEBUG/INFO/WARN/ERROR (subject to LOG_MIN_LEVEL)
  # - If healthy: allow WARN/ERROR; allow DEBUG/INFO only when JOB_WRAP_DEBUG=1
  _emit_boundary=0
  if [ "$LOG_DEGRADED" -eq 1 ]; then
    _emit_boundary=1
  else
    case "$_lvl" in
      WARN|ERROR) _emit_boundary=1 ;;
      *) [ "${JOB_WRAP_DEBUG:-0}" = "1" ] && _emit_boundary=1 ;;
    esac
  fi

  # Multiline diagnostics: keep boundary single-line; write full text to bootstrap.
  case "$_msg" in
    *"$_NL"*)
      if [ -n "${WRAP_BOOT_LOG:-}" ]; then
        {
          printf '%s: WRAP: (multiline diagnostic; full text follows)\n' "$_lvl"
          printf '%s\n' "$_msg"
        } >>"$WRAP_BOOT_LOG" 2>/dev/null || :
      fi
      if [ "$_emit_boundary" -eq 1 ]; then
        printf '%s: WRAP: multiline diagnostic (see bootstrap: %s)\n' "$_lvl" "${WRAP_BOOT_LOG:-<unavailable>}" >&2
      fi
      return 0
      ;;
  esac

  if [ "$_emit_boundary" -eq 1 ]; then
    printf '%s: WRAP: %s\n' "$_lvl" "$_msg" >&2
  fi

  if [ -n "${WRAP_BOOT_LOG:-}" ]; then
    printf '%s: WRAP: %s\n' "$_lvl" "$_msg" >>"$WRAP_BOOT_LOG" 2>/dev/null || :
  fi

  return 0
}

_wrap_debug() { _wrap_emit DEBUG "$*"; }
_wrap_info()  { _wrap_emit INFO  "$*"; }
_wrap_warn()  { _wrap_emit WARN  "$*"; }
_wrap_error() { _wrap_emit ERROR "$*"; }

###############################################################################
# Invocation checks
###############################################################################

if [ "$JOB_WRAP_ACTIVE" = "1" ]; then
  _wrap_error "recursion guard: job-wrap already active"
  exit "$WRAP_E_INVOCATION"
fi

if [ $# -lt 1 ]; then
  _wrap_error "usage: job-wrap.sh LEAF_PATH [args...]"
  exit "$WRAP_E_INVOCATION"
fi

LEAF_PATH=$1
shift

JOB_WRAP_ACTIVE=1
export JOB_WRAP_ACTIVE

###############################################################################
# Resolve wrapper paths
###############################################################################

WRAP_DIR=$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd) || {
  _wrap_error "cannot resolve wrapper directory"
  exit "$WRAP_E_INIT"
}

REPO_ROOT=$(CDPATH= cd "$WRAP_DIR/.." 2>/dev/null && pwd) || {
  _wrap_error "cannot resolve repo root from rebuild layout"
  exit "$WRAP_E_INIT"
}

# Default LOG_LIB_DIR to wrapper dir unless caller overrides.
LOG_LIB_DIR=${LOG_LIB_DIR:-$WRAP_DIR}

###############################################################################
# Bootstrap log file (best-effort)
###############################################################################

# Ensure LOG_ROOT exists or degrade gracefully.
LOG_ROOT=${LOG_ROOT:-"$REPO_ROOT/logs"}
LOG_BUCKET=${LOG_BUCKET:-other}
LOG_KEEP_COUNT=${LOG_KEEP_COUNT:-10}

_boot_dir="$LOG_ROOT/_bootstrap"
if mkdir -p "$_boot_dir" 2>/dev/null; then
  # deterministic-ish: include JOB_NAME later; start with pid marker
  WRAP_BOOT_LOG="$_boot_dir/jobwrap-bootstrap-$$.log"
  : >"$WRAP_BOOT_LOG" 2>/dev/null || WRAP_BOOT_LOG=""
else
  WRAP_BOOT_LOG=""
fi

_wrap_debug "bootstrap diagnostics: WRAP_DIR=$WRAP_DIR REPO_ROOT=$REPO_ROOT LOG_ROOT=$LOG_ROOT LOG_LIB_DIR=$LOG_LIB_DIR"

###############################################################################
# Temp capture file selection
###############################################################################

_tmp=""
_capture_setup_ok=0

# Prefer TMPDIR if usable; otherwise degrade to passthrough.
TMPDIR=${TMPDIR:-/tmp}
if [ -d "$TMPDIR" ] && [ -w "$TMPDIR" ]; then
  _tmp="$TMPDIR/jobwrap.capture.${$}.$$"
  if : >"$_tmp" 2>/dev/null; then
    _capture_setup_ok=1
  fi
fi

if [ "$_capture_setup_ok" -ne 1 ]; then
  CAPTURE_MODE="passthrough"
  _wrap_warn "cannot create temp capture file; using passthrough mode"
fi

###############################################################################
# Derive JOB_NAME
###############################################################################

_leaf_base=$(basename "$LEAF_PATH" 2>/dev/null || printf '%s' "$LEAF_PATH")
JOB_NAME=${JOB_NAME:-${_leaf_base%.*}}

# Contract: job name must be safe for paths
case "$JOB_NAME" in
  ""|*[!A-Za-z0-9._-]*)
    _wrap_error "invalid JOB_NAME derived from leaf: $JOB_NAME"
    exit "$WRAP_E_INVOCATION"
    ;;
  esac

export JOB_NAME

# Update bootstrap log name now that JOB_NAME exists (best-effort)
if [ -n "${WRAP_BOOT_LOG:-}" ]; then
  _new_boot="$_boot_dir/${JOB_NAME}-bootstrap-$(date +%s 2>/dev/null || echo $$).log"
  if mv "$WRAP_BOOT_LOG" "$_new_boot" 2>/dev/null; then
    WRAP_BOOT_LOG="$_new_boot"
  fi
fi

###############################################################################
# Source log library and initialize
###############################################################################

# Source log lib
if ! . "$LOG_LIB_DIR/log.sh" 2>/dev/null; then
  _wrap_error "cannot source log library: $LOG_LIB_DIR/log.sh"
  exit "$WRAP_E_INIT"
fi

# Contain log_init stdout (stdout is sacred)
_li_out="$TMPDIR/jobwrap.log_init.out.${JOB_NAME}.$$"
rm -f "$_li_out" 2>/dev/null || :
: >"$_li_out" 2>/dev/null || _li_out=/dev/null

_li_rc=0
(
  # shellcheck disable=SC2039
  log_init "$LOG_ROOT" "$LOG_BUCKET" "$JOB_NAME" "$LOG_KEEP_COUNT"
) >"$_li_out" 2>/dev/null
_li_rc=$?

if [ -s "$_li_out" ]; then
  LOG_DEGRADED=1
  _wrap_warn "contract violation contained: log_init wrote to stdout (degrading)"
  if [ -n "${WRAP_BOOT_LOG:-}" ]; then
    {
      printf 'BOOTSTRAP WARN: log_init stdout leak contained\n'
      printf '--- log_init stdout ---\n'
      cat "$_li_out" 2>/dev/null || :
      printf '\n'
    } >>"$WRAP_BOOT_LOG" 2>/dev/null || :
  fi
fi

rm -f "$_li_out" 2>/dev/null || :

case "$_li_rc" in
  0)
    LOG_DEGRADED=0
    ;;
  10)
    LOG_DEGRADED=1
    _wrap_warn "logger init operational failure; centralized logging degraded"
    ;;
  11)
    _wrap_error "logger init misuse; aborting wrapper init"
    exit "$WRAP_E_INIT"
    ;;
  *)
    LOG_DEGRADED=1
    _wrap_warn "logger init unexpected rc=$_li_rc; centralized logging degraded"
    ;;
esac

###############################################################################
# Cleanup
###############################################################################

_cleanup() {
  rm -f "$_tmp" 2>/dev/null || :
}
trap _cleanup 0 1 2 15

###############################################################################
# Run leaf
###############################################################################

_leaf_rc=0

if [ "$CAPTURE_MODE" = "passthrough" ]; then
  "$LEAF_PATH" "$@"
  _leaf_rc=$?
else
  # CAPTURE_MODE=file
  "$LEAF_PATH" "$@" 2>"$_tmp"
  _leaf_rc=$?
fi

###############################################################################
# Capture forwarding
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
  else
    # Option A: fail-open visibility (degraded logger; replay captured leaf stderr to boundary)
    cat "$_tmp" >&2 2>/dev/null || :
  fi
fi

###############################################################################
# Optional commit orchestration
###############################################################################

COMMIT_MODE=${COMMIT_MODE:-off}
COMMIT_MESSAGE=${COMMIT_MESSAGE:-""}

if [ "$_leaf_rc" -eq 0 ] && [ "$COMMIT_MODE" != "off" ]; then
  _cl="$TMPDIR/jobwrap.commit-list.${JOB_NAME}.$$"
  rm -f "$_cl" 2>/dev/null || :
  : >"$_cl" 2>/dev/null || _cl=""

  if [ -n "${_cl:-}" ]; then
    COMMIT_LIST_FILE="$_cl"
    export COMMIT_LIST_FILE
  else
    COMMIT_LIST_FILE=""
    export COMMIT_LIST_FILE
    _wrap_warn "cannot create COMMIT_LIST_FILE; commit orchestration disabled"
  fi

  # Leaf can append to COMMIT_LIST_FILE during its run; here we act after leaf.
  if [ -n "${COMMIT_LIST_FILE:-}" ] && [ -s "$COMMIT_LIST_FILE" ]; then
    _cl2="$TMPDIR/jobwrap.commit-list.filtered.${JOB_NAME}.$$"
    rm -f "$_cl2" 2>/dev/null || :
    : >"$_cl2" 2>/dev/null || _cl2=""

    if [ -n "${_cl2:-}" ]; then
      # Filter: remove blank lines and comments
      # (POSIX: sed)
      sed -e '/^[[:space:]]*$/d' -e '/^[[:space:]]*#/d' <"$COMMIT_LIST_FILE" >"$_cl2" 2>/dev/null || :

      if [ -s "$_cl2" ]; then
        _wrap_info "commit requested: mode=$COMMIT_MODE"

        "$LOG_LIB_DIR/commit.sh" "$REPO_ROOT" "$COMMIT_MESSAGE" $(cat "$_cl2")
        _c_rc=$?

        case "$_c_rc" in
          0|3)
            : # success or "no changes"
            ;;
          *)
            _wrap_error "commit helper failed (rc=$_c_rc)"
            exit "$WRAP_E_COMMIT"
            ;;
        esac
      fi

      rm -f "$_cl2" 2>/dev/null || :
    fi
  fi

  rm -f "$_cl" 2>/dev/null || :
fi

exit "$_leaf_rc"
