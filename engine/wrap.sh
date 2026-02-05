#!/bin/sh
# engine/wrap.sh
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

  # When centralized logging is healthy and internal debug is enabled,
  # mirror wrapper diagnostics into the per-run log via log_capture.
  # This keeps bootstrap logs reserved for bootstrap/degraded logging evidence.
  _emit_runlog=0
  if [ "${LOG_DEGRADED:-1}" -eq 0 ] && { [ "${JOB_WRAP_DEBUG:-0}" = "1" ] || [ "${LOG_MIN_LEVEL:-INFO}" = "DEBUG" ]; }; then
    _emit_runlog=1
  fi

  # Default boundary emission rules:
  # - If degraded: allow DEBUG/INFO/WARN/ERROR (subject to LOG_MIN_LEVEL)
  # - If healthy: allow WARN/ERROR; allow DEBUG/INFO only when JOB_WRAP_DEBUG=1
  _emit_boundary=0
  if [ "$LOG_DEGRADED" -eq 1 ]; then
    _emit_boundary=1
  else
    case "$_lvl" in
      WARN|ERROR) _emit_boundary=1 ;;
      *)
        if [ "${JOB_WRAP_DEBUG:-0}" = "1" ] || [ "${LOG_MIN_LEVEL:-INFO}" = "DEBUG" ]; then
          _emit_boundary=1
        fi
        ;;
    esac
  fi

  # Multiline diagnostics: keep boundary single-line; write full text to bootstrap/runlog.
  # Detect newline in a POSIX-safe way (no command substitution / no external tools):
  # If removing the shortest prefix ending in a literal newline changes the string,
  # then the string contained a newline.
  if [ "${_msg#*
}" != "$_msg" ]; then
      # Healthy logging: write full multiline content into the per-run log (opt-in).
      if [ "$_emit_runlog" -eq 1 ]; then
        # Preserve newlines by streaming the message as-is.
        # Each line will be formatted by the logger with LEVEL=$_lvl.
        printf '%s\n' "$_msg" | log_capture "$_lvl" >/dev/null 2>/dev/null || :
      else
        # Degraded / pre-init: preserve full multiline evidence in bootstrap log.
        if [ -n "${WRAP_BOOT_LOG:-}" ]; then
          {
            printf '%s: WRAP: (multiline diagnostic; full text follows)\n' "$_lvl"
            printf '%s\n' "$_msg"
          } >>"$WRAP_BOOT_LOG" 2>/dev/null || :
        fi
      fi
      if [ "$_emit_boundary" -eq 1 ]; then
        if [ "$_emit_runlog" -eq 1 ]; then
          printf '%s: WRAP: multiline diagnostic (see run log)\n' "$_lvl" >&2
        else
          printf '%s: WRAP: multiline diagnostic (see bootstrap: %s)\n' "$_lvl" "${WRAP_BOOT_LOG:-<unavailable>}" >&2
        fi
      fi
      return 0
  fi

  if [ "$_emit_boundary" -eq 1 ]; then
    printf '%s: WRAP: %s\n' "$_lvl" "$_msg" >&2
  fi

  # Healthy logging: mirror wrapper diagnostics into the per-run log (opt-in).
  if [ "$_emit_runlog" -eq 1 ]; then
    log_capture "$_lvl" <<EOF >/dev/null 2>/dev/null || :
${_lvl}: WRAP: ${_msg}
EOF
  else
    # Bootstrap logging: only when degraded / pre-init.
    if [ -n "${WRAP_BOOT_LOG:-}" ] && [ "${LOG_DEGRADED:-1}" -eq 1 ]; then
      printf '%s: WRAP: %s\n' "$_lvl" "$_msg" >>"$WRAP_BOOT_LOG" 2>/dev/null || :
    fi
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

# Debug run override: when JOB_WRAP_DEBUG=1, force minimum log level to DEBUG
# so *everything* is visible (wrapper + leaf capture + logger formatting policy).
if [ "${JOB_WRAP_DEBUG:-0}" = "1" ]; then
  LOG_MIN_LEVEL=DEBUG
  export LOG_MIN_LEVEL
fi

###############################################################################
# Resolve wrapper paths
###############################################################################

WRAP_DIR=$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd) || {
  _wrap_error "cannot resolve wrapper directory"
  exit "$WRAP_E_INIT"
}

REPO_ROOT=$(CDPATH= cd "$WRAP_DIR/.." 2>/dev/null && pwd) || {
  _wrap_error "cannot resolve repo root from engine layout"
  exit "$WRAP_E_INIT"
}

# Default LOG_ROOT: sibling of repo at ../logs (i.e., parent-of-repo-root/logs).
# Respect an explicit LOG_ROOT if provided by caller.
if [ -z "${LOG_ROOT+x}" ] || [ -z "${LOG_ROOT:-}" ]; then
  repo_parent=$(CDPATH= cd -- "$REPO_ROOT/.." 2>/dev/null && pwd -P || printf '')
  if [ -n "$repo_parent" ]; then
    LOG_ROOT="$repo_parent/logs"
  else
    LOG_ROOT="$REPO_ROOT/logs"
  fi
fi

export LOG_ROOT

###############################################################################
# Resolve leaf by name (convenience)
###############################################################################
#
# If LEAF_PATH has no '/' component, treat it as a script name and try to resolve
# it to a path within the repo, so callers don't need to specify the full path.
#
# Override search order with:
#   JOB_WRAP_SEARCH_PATH="/path/a:/path/b"
#
# Default search path prefers common repo locations.
: "${JOB_WRAP_SEARCH_PATH:=$REPO_ROOT/bin:$REPO_ROOT/jobs:$REPO_ROOT/generators:$REPO_ROOT/engine:$REPO_ROOT/utils:$REPO_ROOT/scripts}"

LEAF_USE_SH=0

case "$LEAF_PATH" in
  */*)
    # Already a path (relative or absolute). Leave it alone.
    ;;
  *)
    _resolved=""

    # 1) Search configured path list (fast path).
    if [ -n "$JOB_WRAP_SEARCH_PATH" ]; then
      _old_ifs=$IFS
      IFS=:
      for _d in $JOB_WRAP_SEARCH_PATH; do
        [ -n "$_d" ] || continue
        _cand="$_d/$LEAF_PATH"
        if [ -x "$_cand" ]; then
          _resolved=$_cand
          break
        fi
        # If it's a readable .sh but not executable, allow it (we'll run via sh).
        case "$_cand" in
          *.sh)
            if [ -f "$_cand" ] && [ -r "$_cand" ]; then
              _resolved=$_cand
              LEAF_USE_SH=1
              break
            fi
            ;;
        esac
      done
      IFS=$_old_ifs
    fi

    # 2) Search repo recursively for an executable match (prune .git and logs).
    if [ -z "$_resolved" ]; then
      _hits=$(
        find "$REPO_ROOT" \
          \( -path "$REPO_ROOT/.git" -o -path "$REPO_ROOT/logs" \) -prune -o \
          -type f -name "$LEAF_PATH" -perm -111 -print 2>/dev/null \
          | sort | head -n 1 || true
      )
      if [ -n "$_hits" ]; then
        _resolved=$_hits
      fi
    fi

    # 3) If not found as executable, allow any readable .sh anywhere in repo.
    if [ -z "$_resolved" ]; then
      _hits=$(
        find "$REPO_ROOT" \
          \( -path "$REPO_ROOT/.git" -o -path "$REPO_ROOT/logs" \) -prune -o \
          -type f -name "$LEAF_PATH" -print 2>/dev/null \
          | sort | head -n 1 || true
      )
      if [ -n "$_hits" ]; then
        _resolved=$_hits
        case "$_resolved" in
          *.sh) LEAF_USE_SH=1 ;;
        esac
      fi
    fi

    # 4) Finally, try PATH (command -v).
    if [ -z "$_resolved" ]; then
      _hits=$(command -v "$LEAF_PATH" 2>/dev/null || true)
      [ -n "$_hits" ] && _resolved=$_hits
    fi

    if [ -z "$_resolved" ]; then
      _wrap_error "leaf not found: $LEAF_PATH"
      exit 127
    fi

    LEAF_PATH=$_resolved
    ;;
esac

# Default LOG_LIB_DIR to wrapper dir unless caller overrides.
LOG_LIB_DIR=${LOG_LIB_DIR:-$WRAP_DIR}
export LOG_LIB_DIR

###############################################################################
# Temp/capture feasibility (TMPDIR contract)
###############################################################################

TMPDIR=${TMPDIR:-/tmp}
TMP_OK=0
if [ -d "$TMPDIR" ] && [ -w "$TMPDIR" ]; then
  TMP_OK=1
fi
_wrap_debug "env: JOB_WRAP_DEBUG=${JOB_WRAP_DEBUG:-0} LOG_MIN_LEVEL=${LOG_MIN_LEVEL:-INFO} TMPDIR=$TMPDIR TMP_OK=$TMP_OK"

###############################################################################
# Bootstrap log file (best-effort)
###############################################################################

LOG_KEEP_COUNT=${LOG_KEEP_COUNT:-10}
export LOG_ROOT LOG_KEEP_COUNT

_boot_dir="$LOG_ROOT/_bootstrap"
if mkdir -p "$_boot_dir" 2>/dev/null; then
  WRAP_BOOT_LOG="$_boot_dir/jobwrap-bootstrap-$$.log"
  : >"$WRAP_BOOT_LOG" 2>/dev/null || WRAP_BOOT_LOG=""
else
  WRAP_BOOT_LOG=""
fi

# TEST EXPECTATION: when LOG_MIN_LEVEL=DEBUG, boundary should include this line.
if [ "${LOG_MIN_LEVEL:-INFO}" = "DEBUG" ]; then
  printf '%s\n' "DEBUG: WRAP: bootstrap diagnostics" >&2
fi

_wrap_debug "bootstrap diagnostics: WRAP_DIR=$WRAP_DIR REPO_ROOT=$REPO_ROOT LOG_ROOT=$LOG_ROOT LOG_LIB_DIR=$LOG_LIB_DIR"

###############################################################################
# Temp capture file selection (CAPTURE_MODE)
###############################################################################

_tmp=""
_capture_setup_ok=0

if [ "$TMP_OK" -eq 1 ]; then
  _tmp="$TMPDIR/jobwrap.capture.$$"
  if : >"$_tmp" 2>/dev/null; then
    _capture_setup_ok=1
  fi
fi

if [ "$_capture_setup_ok" -ne 1 ]; then
  CAPTURE_MODE="passthrough"
  _wrap_warn "cannot create temp capture file; using passthrough mode"
fi
_wrap_debug "capture: CAPTURE_MODE=$CAPTURE_MODE tmp_capture=${_tmp:-<unset>}"

###############################################################################
# Derive JOB_NAME
###############################################################################

_leaf_base=$(basename "$LEAF_PATH" 2>/dev/null || printf '%s' "$LEAF_PATH")
JOB_NAME=${JOB_NAME:-${_leaf_base%.*}}

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
_wrap_debug "job: JOB_NAME=$JOB_NAME LEAF_PATH=$LEAF_PATH LEAF_USE_SH=${LEAF_USE_SH:-0} WRAP_BOOT_LOG=${WRAP_BOOT_LOG:-<unset>}"

###############################################################################
# Source log library and initialize
###############################################################################

# Make init failure deterministic across sh variants: check readability first.
if [ ! -r "$LOG_LIB_DIR/log.sh" ]; then
  _wrap_error "cannot source log library: $LOG_LIB_DIR/log.sh"
  exit "$WRAP_E_INIT"
fi

# Source log lib (do not silence failures)
if ! . "$LOG_LIB_DIR/log.sh" 2>/dev/null; then
  _wrap_error "cannot source log library: $LOG_LIB_DIR/log.sh"
  exit "$WRAP_E_INIT"
fi

# Contain log_init stdout when possible; otherwise keep stdout sacred by discarding.
_li_rc=0
_li_out=""
_li_err=""

if [ "$TMP_OK" -eq 1 ]; then
  _li_out="$TMPDIR/jobwrap.log_init.out.${JOB_NAME}.$$"
  _li_err="$TMPDIR/jobwrap.log_init.err.${JOB_NAME}.$$"
  rm -f "$_li_out" "$_li_err" 2>/dev/null || :
  : >"$_li_out" 2>/dev/null || _li_out=""
  : >"$_li_err" 2>/dev/null || _li_err=""

  if [ -n "${_li_out:-}" ] && [ -n "${_li_err:-}" ]; then
    {
      log_init "$JOB_NAME" "${LOG_MIN_LEVEL:-INFO}"
    } >"$_li_out" 2>"$_li_err"
    _li_rc=$?
  else
    LOG_DEGRADED=1
    _wrap_warn "cannot create log_init containment files; running log_init with stdout discarded (degraded)"
    log_init "$JOB_NAME" "${LOG_MIN_LEVEL:-INFO}" >/dev/null 2>/dev/null
    _li_rc=$?
  fi
else
  LOG_DEGRADED=1
  _wrap_warn "TMPDIR unusable; running log_init with stdout discarded (degraded)"
  log_init "$JOB_NAME" "${LOG_MIN_LEVEL:-INFO}" >/dev/null 2>/dev/null
  _li_rc=$?
fi

if [ -n "${_li_out:-}" ] && [ -s "$_li_out" ]; then
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

rm -f "$_li_out" "$_li_err" 2>/dev/null || :

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
_wrap_debug "log-init: rc=$_li_rc LOG_DEGRADED=$LOG_DEGRADED LOG_BUCKET=${LOG_BUCKET:-<unset>} LOG_FILE=${LOG_FILE:-<unset>} LOG_SINK_FD=${LOG_SINK_FD:-<unset>}"

###############################################################################
# Optional commit list file wiring (MUST exist before leaf runs)
###############################################################################

# Vault root (artifact destination root).
# Notes live in the vault, not the tools repo.
# Resolution order:
#   1) VAULT_ROOT (explicit override)
#   2) VAULT_PATH
#   3) hard default: /home/obsidian/vaults/Main
VAULT_ROOT=${VAULT_ROOT:-}
if [ -z "$VAULT_ROOT" ]; then
  VAULT_ROOT=${VAULT_PATH:-/home/obsidian/vaults/Main}
fi
export VAULT_ROOT

# Back-compat alias: commit subsystem still uses COMMIT_WORK_TREE.
COMMIT_WORK_TREE=${COMMIT_WORK_TREE:-$VAULT_ROOT}
export COMMIT_WORK_TREE

COMMIT_MODE=${COMMIT_MODE:-required}
COMMIT_MESSAGE=${COMMIT_MESSAGE:-""}

# Default commit message (wrapper-owned):
# commit.sh requires a non-empty message. If caller didn't supply one,
# derive a stable, informative default from JOB_NAME.
if [ -z "${COMMIT_MESSAGE:-}" ]; then
  COMMIT_MESSAGE="job: ${JOB_NAME}"
fi

COMMIT_LIST_FILE=""
if [ "$COMMIT_MODE" != "off" ]; then
  if [ "$TMP_OK" -eq 1 ]; then
    _cl="$TMPDIR/jobwrap.commit-list.${JOB_NAME}.$$"
    rm -f "$_cl" 2>/dev/null || :
    : >"$_cl" 2>/dev/null || _cl=""

    if [ -n "${_cl:-}" ]; then
      COMMIT_LIST_FILE="$_cl"
    else
      COMMIT_LIST_FILE=""
      _wrap_warn "cannot create COMMIT_LIST_FILE; commit orchestration disabled"
    fi
  else
    COMMIT_LIST_FILE=""
    _wrap_warn "TMPDIR unusable; cannot create COMMIT_LIST_FILE; commit orchestration disabled"
  fi

  export COMMIT_LIST_FILE
fi
_wrap_debug "commit-setup: COMMIT_MODE=$COMMIT_MODE COMMIT_MESSAGE=$COMMIT_MESSAGE VAULT_ROOT=$VAULT_ROOT COMMIT_WORK_TREE=$COMMIT_WORK_TREE COMMIT_LIST_FILE=${COMMIT_LIST_FILE:-<unset>}"

###############################################################################
# Cleanup
###############################################################################

_cleanup() {
  # Remove temp capture file.
  if [ -n "${_tmp:-}" ]; then
    rm -f -- "$_tmp" 2>/dev/null || :
  fi

  # Remove empty bootstrap log if logging ended healthy.
  if [ "${LOG_DEGRADED:-1}" -eq 0 ] && [ -n "${WRAP_BOOT_LOG:-}" ]; then
    if [ -f "$WRAP_BOOT_LOG" ] && [ ! -s "$WRAP_BOOT_LOG" ]; then
      rm -f -- "$WRAP_BOOT_LOG" 2>/dev/null || :
    fi
  fi

  # If the bootstrap dir is now empty, remove it (best-effort).
  if [ "${LOG_DEGRADED:-1}" -eq 0 ] && [ -n "${_boot_dir:-}" ]; then
    rmdir -- "$_boot_dir" 2>/dev/null || :
  fi
}
trap _cleanup 0 1 2 15

###############################################################################
# Run leaf
###############################################################################

_leaf_rc=0

if [ "$CAPTURE_MODE" = "passthrough" ]; then
  if [ "${LEAF_USE_SH:-0}" -eq 1 ]; then
    sh "$LEAF_PATH" "$@"
  else
    "$LEAF_PATH" "$@"
  fi
  _leaf_rc=$?
else
  if [ "${LEAF_USE_SH:-0}" -eq 1 ]; then
    sh "$LEAF_PATH" "$@" 2>"$_tmp"
  else
    "$LEAF_PATH" "$@" 2>"$_tmp"
  fi
  _leaf_rc=$?
fi
_wrap_debug "leaf: rc=$_leaf_rc"

###############################################################################
# Capture forwarding
###############################################################################

if [ "$CAPTURE_MODE" = "file" ] && [ -s "$_tmp" ]; then
  if [ "$LOG_DEGRADED" -eq 0 ]; then
    _lc_err=""
    if [ "$TMP_OK" -eq 1 ]; then
      _lc_err="$TMPDIR/jobwrap.capture.err.${JOB_NAME}.$$"
      rm -f "$_lc_err" 2>/dev/null || :
      : >"$_lc_err" 2>/dev/null || _lc_err=""
    fi
    _wrap_debug "capture-forward: tmp_has_data=1 lc_err=${_lc_err:-<unset>}"
    if [ -n "${_lc_err:-}" ]; then
      log_capture UNDEF <"$_tmp" >/dev/null 2>"$_lc_err"
    else
      log_capture UNDEF <"$_tmp" >/dev/null 2>/dev/null
    fi
    _lc_rc=$?

    if [ "$_lc_rc" -ne 0 ]; then
      LOG_DEGRADED=1
      _wrap_warn "log_capture failed; centralized logging degraded (replaying leaf stderr to boundary)"

      if [ -n "${WRAP_BOOT_LOG:-}" ] && [ -n "${_lc_err:-}" ]; then
        {
          printf 'BOOTSTRAP WARN: log_capture failure\n'
          printf 'log_capture exit=%s\n' "$_lc_rc"
          printf '--- log_capture stderr ---\n'
          cat "$_lc_err" 2>/dev/null || :
          printf '\n--- captured leaf stderr (replayed to boundary) ---\n'
          cat "$_tmp" 2>/dev/null || :
        } >>"$WRAP_BOOT_LOG" 2>/dev/null || :
      fi

      cat "$_tmp" >&2 2>/dev/null || :
    fi
  else
    cat "$_tmp" >&2 2>/dev/null || :
  fi
fi
if [ "$CAPTURE_MODE" = "file" ] && [ -n "${_tmp:-}" ] && [ ! -s "$_tmp" ]; then
  _wrap_debug "capture-forward: tmp_has_data=0"
fi

###############################################################################
# Optional commit orchestration
###############################################################################

if [ "$_leaf_rc" -eq 0 ] && [ "$COMMIT_MODE" != "off" ]; then
  _wrap_debug "commit gate: leaf_rc=$_leaf_rc COMMIT_MODE=$COMMIT_MODE COMMIT_LIST_FILE=${COMMIT_LIST_FILE:-<unset>}"
  _commit_fatal=0
  [ "$COMMIT_MODE" = "required" ] && _commit_fatal=1
  _wrap_debug "commit policy: mode=$COMMIT_MODE fatal=$_commit_fatal"

  # Warn loudly if commit mode is enabled but we never got a usable list.
  if [ -z "${COMMIT_LIST_FILE:-}" ] || [ ! -s "$COMMIT_LIST_FILE" ]; then
    _wrap_warn "COMMIT_MODE=$COMMIT_MODE but no commit list provided; nothing to commit"
  fi

  if [ -n "${COMMIT_LIST_FILE:-}" ] && [ -s "$COMMIT_LIST_FILE" ]; then
    _cl2=""
    if [ "$TMP_OK" -eq 1 ]; then
      _cl2="$TMPDIR/jobwrap.commit-list.filtered.${JOB_NAME}.$$"
      rm -f "$_cl2" 2>/dev/null || :
      : >"$_cl2" 2>/dev/null || _cl2=""
    fi

    if [ -n "${_cl2:-}" ]; then
      sed -e '/^[[:space:]]*$/d' -e '/^[[:space:]]*#/d' <"$COMMIT_LIST_FILE" >"$_cl2" 2>/dev/null || :

      if [ ! -s "$_cl2" ]; then
        _wrap_warn "commit skipped: filtered commit list empty (only blanks/comments?)"
      fi

      if [ -s "$_cl2" ]; then
        # Optional visibility: record the exact filtered list to bootstrap.
        _wrap_debug "commit list (filtered): writing to bootstrap"
        if [ -n "${WRAP_BOOT_LOG:-}" ]; then
          {
            printf 'DEBUG: WRAP: commit list (filtered):\n'
            cat "$_cl2" 2>/dev/null || :
            printf '\n'
          } >>"$WRAP_BOOT_LOG" 2>/dev/null || :
        fi

        # Build argv safely from newline-delimited list (preserve spaces).
        set --
        while IFS= read -r _p; do
          [ -n "$_p" ] || continue
          set -- "$@" "$_p"
        done <"$_cl2"

        _wrap_info "commit requested: mode=$COMMIT_MODE"
        "$LOG_LIB_DIR/commit.sh" "$COMMIT_WORK_TREE" "$COMMIT_MESSAGE" "$@"
        _c_rc=$?
        _wrap_debug "commit: helper_rc=$_c_rc"

        case "$_c_rc" in
          0|3)
            : # success or "no changes"
            ;;
          *)
            if [ "$_commit_fatal" -eq 1 ]; then
              _wrap_error "commit helper failed (rc=$_c_rc)"
              exit "$WRAP_E_COMMIT"
            fi
            _wrap_warn "commit helper failed (rc=$_c_rc); continuing (mode=$COMMIT_MODE)"
            ;;
        esac
      fi

      rm -f "$_cl2" 2>/dev/null || :
    fi
  fi
fi

if [ -n "${COMMIT_LIST_FILE:-}" ]; then
  rm -f -- "$COMMIT_LIST_FILE" 2>/dev/null || :
fi

###############################################################################
# Debug summary (end-of-run observability)
###############################################################################
if [ "${JOB_WRAP_DEBUG:-0}" = "1" ] || [ "${LOG_MIN_LEVEL:-INFO}" = "DEBUG" ]; then
  _wrap_debug "summary: JOB_NAME=$JOB_NAME leaf_rc=$_leaf_rc LOG_DEGRADED=$LOG_DEGRADED CAPTURE_MODE=$CAPTURE_MODE"
  _wrap_debug "summary: LOG_ROOT=$LOG_ROOT LOG_BUCKET=${LOG_BUCKET:-<unset>} LOG_FILE=${LOG_FILE:-<unset>} LOG_SINK_FD=${LOG_SINK_FD:-<unset>}"
  _wrap_debug "summary: COMMIT_MODE=$COMMIT_MODE COMMIT_LIST_FILE=${COMMIT_LIST_FILE:-<unset>}"
fi

exit "$_leaf_rc"
