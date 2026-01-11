#!/bin/sh
# utils/core/log-format.sh
# Author: deadhedd
# License: MIT
# shellcheck shell=sh
#
# Purpose (contract):
# - Sanitize messages (CR stripped; non-ASCII replaced)
# - Gate levels (policy provided by higher authority: log.sh / wrapper)
# - Stamp each line with a local timestamp (explicitly labeled in-format)
#
# Library-only: MUST be sourced (never executed).
# Dependency: datetime.sh MUST be sourced before this file (by log.sh).
#
# Timestamp requirement:
# - Requires dt_now_local_log_ts (returns "YYYY-MM-DD HH:MM:SS", local)
# - No fallback paths (missing datetime is an operational failure)
#
# Worker model:
# - This file does not set defaults or configure policy.
# - Level policy (min level) is provided by the coordinator per call.
# - No PATH/cd/traps; minimal surface area.
#
# Output rule:
# - This module MUST NOT emit formatted log lines to stdout as user-visible output.
# - Formatted output is returned to the caller via an output variable.
# - Internal pipelines may write to stdout when captured by the caller.

# Refuse execution; must be sourced.
(return 0 2>/dev/null) || {
  printf '%s\n' "Error: log-format.sh is a library and must be sourced, not executed." >&2
  exit 2
}

# Prevent double-sourcing (internal guard).
if [ "${_lf_loaded:-0}" = "1" ]; then
  return 0
fi
_lf_loaded=1

# -----------------------------
# Internal helpers (all _lf_)
# -----------------------------

_lf_die() {
  printf '%s\n' "Error: $*" >&2
  return 10
}

_lf_level_val() {
  case "${1:-}" in
    DEBUG) printf '%s' 10 ;;
    INFO)  printf '%s' 20 ;;
    WARN)  printf '%s' 30 ;;
    ERROR) printf '%s' 40 ;;
    *) return 10 ;;
  esac
}

_lf_validate_level_name() {
  _lf_level_val "${1:-}" >/dev/null 2>&1 || {
    _lf_die "invalid level: ${1:-} (expected DEBUG|INFO|WARN|ERROR)"
    return 10
  }
  return 0
}

_lf_allow_level() {
  # Args:
  #   $1 = MIN_LEVEL (DEBUG|INFO|WARN|ERROR)
  #   $2 = MSG_LEVEL (DEBUG|INFO|WARN|ERROR)
  _lf_min_val=$(_lf_level_val "$1") || return 10
  _lf_msg_val=$(_lf_level_val "$2") || return 10

  [ "$_lf_msg_val" -ge "$_lf_min_val" ] && return 0
  return 4
}

_lf_timestamp() {
  # Dependency must be provided by datetime.sh (sourced by log.sh).
  _lf_ts=$(dt_now_local_log_ts) || {
    _lf_die "failed to obtain local timestamp"
    return 10
  }
  [ -n "$_lf_ts" ] || {
    _lf_die "failed to obtain local timestamp"
    return 10
  }

  printf '%s' "$_lf_ts"
}

_lf_sanitize_ascii() {
  # Reads stdin, writes sanitized text to stdout (caller captures).
  #
  # NOTE:
  # - LC_ALL=C is REQUIRED to force byte-wise semantics.
  # - Ranges rely on ASCII byte ordering (0x20–0x7E).
  # - This is intentional and contractually enforced.
  #
  # Behavior:
  # - strip CR
  # - preserve: tab, newline, printable ASCII
  # - replace all other bytes with '?'
  LC_ALL=C tr -d '\r' | LC_ALL=C tr -c '\t\n\040-\176' '?'
}

_lf_set_var() {
  # Safely set a caller-provided variable name to a value.
  # Args: $1=varname, $2=value (single-line; no newline)
  case "${1:-}" in
    ""|*[!A-Za-z0-9_]*|[0-9]*)
      _lf_die "invalid output variable name: ${1:-}"
      return 10
      ;;
  esac

  _lf_v=${2-}

  # Escape for eval-safe assignment (single-line by contract).
  _lf_v=$(printf '%s' "$_lf_v" | sed \
    -e 's/\\/\\\\/g' \
    -e 's/"/\\"/g' \
    -e 's/`/\\`/g' \
    -e 's/\$/\\$/g'
  ) || {
    _lf_die "failed to escape output value"
    return 10
  }

  eval "$1=\"$_lf_v\""
  return 0
}

# -----------------------------
# Public API (for log.sh)
# -----------------------------

log_format_build_line() {
  # Build a single formatted log line into an output variable.
  #
  # Usage:
  #   log_format_build_line <OUT_VAR> <MIN_LEVEL> <LEVEL> <MESSAGE>
  #
  # Return codes:
  #   0  success; OUT_VAR set
  #   4  gated/suppressed by policy (non-failure; OUT_VAR untouched)
  #   10 operational failure
  #
  # Notes:
  # - MESSAGE must be a single argument and single-line.
  # - This function MUST NOT emit the formatted log line to stdout.
  if [ $# -ne 4 ]; then
    _lf_die "log_format_build_line: OUT_VAR, MIN_LEVEL, LEVEL, and single MESSAGE argument are required"
    return 10
  fi

  _lf_out_var=$1
  _lf_min_level=$2
  _lf_level=$3
  _lf_msg=$4

  _lf_validate_level_name "$_lf_min_level" || return 10
  _lf_validate_level_name "$_lf_level" || return 10

  case "$_lf_msg" in
    *'
'*)
      _lf_die "log_format_build_line: MESSAGE must be single-line"
      return 10
      ;;
  esac

  _lf_allow_level "$_lf_min_level" "$_lf_level"
  _lf_gate_rc=$?
  case "$_lf_gate_rc" in
    0) : ;;
    4) return 4 ;;
    *) _lf_die "log_format_build_line: level gating failed unexpectedly"; return 10 ;;
  esac

  _lf_ts=$(_lf_timestamp) || return 10

  _lf_sanitized=$(printf '%s' "$_lf_msg" | _lf_sanitize_ascii) || {
    _lf_die "log_format_build_line: sanitize failed"
    return 10
  }

  # NOTE:
  # - No trailing newline here.
  # - Sink is responsible for newline emission.
  _lf_line=$(printf '%s [local] %s %s' "$_lf_ts" "$_lf_level" "$_lf_sanitized") || {
    _lf_die "log_format_build_line: format failed"
    return 10
  }

  _lf_set_var "$_lf_out_var" "$_lf_line" || return 10
  return 0
}
