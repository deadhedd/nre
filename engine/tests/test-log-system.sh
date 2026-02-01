#!/bin/sh
# test-log-system.sh
# Author: deadhedd
# License: MIT
# shellcheck shell=sh
#
# Purpose:
# - Smoke/regression tests for the rebuilt logging subsystem (log.sh + helpers).
# - POSIX sh, ASCII-only.
#
# Usage:
#   sh test-log-system.sh [--lib-dir DIR] [--facade PATH]
#
# Defaults assume:
#   rebuild/log.sh
#   rebuild/log-format.sh
#   rebuild/log-sink.sh
#   rebuild/log-capture.sh
#
# Notes:
# - This script creates a sandbox and copies your logging libs into it.
# - It writes a deterministic datetime.sh stub so tests are stable.
# - Adds additional lifecycle + error-path tests (except concurrency/races).
#
# Debug:
#   LOG_TEST_DEBUG=1 sh test-log-system.sh ...

set -u

# Set LOG_TEST_DEBUG=1 to print sandbox paths and diagnostics.
LOG_TEST_DEBUG=${LOG_TEST_DEBUG:-0}

dbg() {
  [ "$LOG_TEST_DEBUG" = "1" ] || return 0
  printf 'DBG: %s\n' "$*" >&2
}

show_file_tail() {
  _p=$1
  _n=${2:-80}
  [ -f "$_p" ] || return 0
  dbg "---- tail $_n of $_p ----"
  tail -n "$_n" "$_p" >&2
  dbg "---- end tail ----"
}

# Find lines with an odd number of double quotes (likely start of the issue).
scan_unbalanced_dquotes() {
  _p=$1
  [ -f "$_p" ] || return 0
  _hits=$(
    awk '
      {
        n=gsub(/"/,"");
        if (n % 2 == 1) print NR ":" $0
      }
    ' "$_p" 2>/dev/null
  )
  if [ -n "$_hits" ]; then
    dbg "UNBALANCED DOUBLE-QUOTE LINES in $_p:"
    printf '%s\n' "$_hits" >&2
  else
    dbg "No odd-count double-quote lines found in $_p"
  fi
}

scan_non_ascii() {
  _p=$1
  [ -f "$_p" ] || return 0

  # Any byte outside: TAB (0x09) and printable ASCII (0x20-0x7E)
  _hits=$(LC_ALL=C grep -n '[^ -~	]' "$_p" 2>/dev/null || true)
  if [ -n "$_hits" ]; then
    dbg "NON-ASCII / CONTROL BYTES in $_p:"
    printf '%s\n' "$_hits" >&2

    # show the lines with visible escapes
    dbg "Showing offending lines with cat -v:"
    printf '%s\n' "$_hits" \
      | sed 's/:.*$//' \
      | while IFS= read -r _ln; do
          [ -n "$_ln" ] || continue
          dbg "line $_ln:"
          sed -n "${_ln}p" "$_p" | cat -v >&2
        done
  else
    dbg "No non-ASCII/control bytes found in $_p"
  fi
}

scan_unbalanced_squotes() {
  _p=$1
  [ -f "$_p" ] || return 0
  _hits=$(
    awk '
      {
        n=gsub(/\047/,""); # count single quotes
        if (n % 2 == 1) print NR ":" $0
      }
    ' "$_p" 2>/dev/null
  )
  if [ -n "$_hits" ]; then
    dbg "UNBALANCED SINGLE-QUOTE LINES in $_p:"
    printf '%s\n' "$_hits" >&2
  else
    dbg "No odd-count single-quote lines found in $_p"
  fi
}

scan_unbalanced_backticks() {
  _p=$1
  [ -f "$_p" ] || return 0
  _hits=$(
    awk '
      {
        n=gsub(/`/,"");
        if (n % 2 == 1) print NR ":" $0
      }
    ' "$_p" 2>/dev/null
  )
  if [ -n "$_hits" ]; then
    dbg "UNBALANCED BACKTICK LINES in $_p:"
    printf '%s\n' "$_hits" >&2
  else
    dbg "No odd-count backtick lines found in $_p"
  fi
}

show_file_bytes_tail() {
  _p=$1
  [ -f "$_p" ] || return 0
  dbg "---- last 256 bytes (od -An -tx1) of $_p ----"
  tail -c 256 "$_p" 2>/dev/null | od -An -tx1 >&2 || :
  dbg "---- end bytes ----"
}

LIB_DIR="./rebuild"
FACADE_PATH="./rebuild/log.sh"

while [ $# -gt 0 ]; do
  case "$1" in
    --lib-dir)
      [ $# -ge 2 ] || { echo "ERROR: --lib-dir requires DIR" >&2; exit 2; }
      LIB_DIR=$2
      shift 2
      ;;
    --facade)
      [ $# -ge 2 ] || { echo "ERROR: --facade requires PATH" >&2; exit 2; }
      FACADE_PATH=$2
      shift 2
      ;;
    *)
      echo "Usage: sh $0 [--lib-dir DIR] [--facade PATH]" >&2
      exit 2
      ;;
  esac
done

# Refuse to run as root unless explicitly allowed.
# Override: ALLOW_ROOT=1 sh test-log-system.sh ...
if [ "$(id -u)" -eq 0 ] && [ "${ALLOW_ROOT:-0}" != "1" ]; then
  echo "ERROR: refusing to run as root (set ALLOW_ROOT=1 to override)" >&2
  exit 2
fi

need_file() {
  _p=$1
  if [ ! -f "$_p" ]; then
    echo "ERROR: missing required file: $_p" >&2
    exit 2
  fi
}

need_file "$FACADE_PATH"
need_file "$LIB_DIR/log-format.sh"
need_file "$LIB_DIR/log-sink.sh"
need_file "$LIB_DIR/log-capture.sh"

# --------------------------------------------------------------------------
# POSIX temp sandbox (no mktemp)
# --------------------------------------------------------------------------
: "${TMPDIR:=/tmp}"
_sandbox="$TMPDIR/logtest.$$"
_i=0
while :; do
  _try="$_sandbox.$_i"
  if (umask 077 && mkdir "$_try") 2>/dev/null; then
    _sandbox="$_try"
    break
  fi
  _i=$(( _i + 1 ))
  if [ "$_i" -gt 200 ]; then
    echo "ERROR: could not create sandbox dir in $TMPDIR" >&2
    exit 2
  fi
done

_sandbox_lib="$_sandbox/lib"
_sandbox_logs="$_sandbox/logs"
mkdir -p "$_sandbox_lib" "$_sandbox_logs" || exit 2

cleanup() {
  rm -rf "$_sandbox"
}

# POSIX traps: 0=EXIT, 1=HUP, 2=INT, 15=TERM
trap cleanup 0 1 2 15

# Copy libs into sandbox
cp "$FACADE_PATH"            "$_sandbox_lib/log.sh" || exit 2
cp "$LIB_DIR/log-format.sh"  "$_sandbox_lib/log-format.sh" || exit 2
cp "$LIB_DIR/log-sink.sh"    "$_sandbox_lib/log-sink.sh" || exit 2
cp "$LIB_DIR/log-capture.sh" "$_sandbox_lib/log-capture.sh" || exit 2

dbg "sandbox=$_sandbox"
dbg "sandbox_lib=$_sandbox_lib"
dbg "sandbox_logs=$_sandbox_logs"

# Sanity: show what got copied
dbg "ls -l sandbox_lib:"
ls -l "$_sandbox_lib" >&2 2>/dev/null || :

# Validate shell syntax of sandboxed log-sink.sh before we ever source it.
if ! sh -n "$_sandbox_lib/log-sink.sh" 2>"$_sandbox/syntax.log"; then
  dbg "sh -n failed for sandbox log-sink.sh:"
  cat "$_sandbox/syntax.log" >&2
  scan_non_ascii "$_sandbox_lib/log-sink.sh"
  scan_unbalanced_dquotes "$_sandbox_lib/log-sink.sh"
  scan_unbalanced_squotes "$_sandbox_lib/log-sink.sh"
  scan_unbalanced_backticks "$_sandbox_lib/log-sink.sh"
  show_file_tail "$_sandbox_lib/log-sink.sh" 200
  show_file_bytes_tail "$_sandbox_lib/log-sink.sh"
  # hard fail early so we don't spam 37 tests with the same root cause
  echo "ERROR: sandbox log-sink.sh has syntax errors (see debug above)" >&2
  exit 2
fi

# Deterministic datetime stub for tests
cat >"$_sandbox_lib/datetime.sh" <<'SHIM'
#!/bin/sh
# datetime.sh (test stub)
# Provides deterministic local timestamps for log tests.

(return 0 2>/dev/null) || { echo "ERROR: datetime.sh must be sourced" >&2; exit 2; }

if [ "${DT_STUB_LOADED:-0}" = "1" ]; then
  return 0
fi
DT_STUB_LOADED=1

_DT_N=${_DT_N:-0}

_dt_inc() {
  _DT_N=$(( _DT_N + 1 ))
}

dt_now_local_iso_no_tz() {
  _dt_inc
  # YYYY-MM-DDTHH:MM:SS
  # Use seconds 01..99 (two digits)
  _s=$_DT_N
  if [ "$_s" -lt 10 ]; then _s="0$_s"; fi
  printf '%s' "2026-01-17T00:00:${_s}"
}

dt_now_local_compact() {
  _dt_inc
  # YYYYmmddTHHMMSS
  _s=$_DT_N
  if [ "$_s" -lt 10 ]; then _s="0$_s"; fi
  printf '%s' "20260117T0000${_s}"
}
SHIM

# --------------------------------------------------------------------------
# Tiny TAP-like runner
# --------------------------------------------------------------------------
_n=0
_fail=0

say() { printf '%s\n' "$*"; }

ok() {
  _n=$(( _n + 1 ))
  say "ok $_n - $*"
}

not_ok() {
  _n=$(( _n + 1 ))
  _fail=$(( _fail + 1 ))
  say "not ok $_n - $*"
}

assert_eq() {
  _got=$1
  _want=$2
  _msg=$3
  if [ "$_got" = "$_want" ]; then
    ok "$_msg"
  else
    not_ok "$_msg (got=$_got want=$_want)"
  fi
}

assert_ne() {
  _got=$1
  _not=$2
  _msg=$3
  if [ "$_got" != "$_not" ]; then
    ok "$_msg"
  else
    not_ok "$_msg (got=$_got unexpected=$_not)"
  fi
}

assert_nonzero() {
  _got=$1
  _msg=$2
  if [ "$_got" -ne 0 ] 2>/dev/null; then
    ok "$_msg"
  else
    not_ok "$_msg (got=$_got expected nonzero)"
  fi
}

# Use -f (regular file) to avoid reliance on test -e in stricter/older sh.
assert_exists() {
  _path=$1
  _msg=$2
  if [ -f "$_path" ]; then
    ok "$_msg"
  else
    not_ok "$_msg (missing file: $_path)"
  fi
}

assert_not_exists() {
  _path=$1
  _msg=$2
  if [ ! -f "$_path" ]; then
    ok "$_msg"
  else
    not_ok "$_msg (unexpectedly exists as file: $_path)"
  fi
}

assert_file_contains() {
  _path=$1
  _needle=$2
  _msg=$3
  if [ ! -f "$_path" ]; then
    not_ok "$_msg (missing file: $_path)"
    return
  fi
  if grep -F "$_needle" "$_path" >/dev/null 2>&1; then
    ok "$_msg"
  else
    not_ok "$_msg (did not find: $_needle)"
  fi
}

assert_file_not_contains() {
  _path=$1
  _needle=$2
  _msg=$3
  if [ ! -f "$_path" ]; then
    not_ok "$_msg (missing file: $_path)"
    return
  fi
  if grep -F "$_needle" "$_path" >/dev/null 2>&1; then
    not_ok "$_msg (unexpectedly found: $_needle)"
  else
    ok "$_msg"
  fi
}

# Reset facade/library guard vars so we can re-source cleanly between tests.
reset_facade_state() {
  for _v in LOG_FACADE_LOADED LOG_SINK_LOADED LOG_CAPTURE_LOADED _lf_loaded DT_STUB_LOADED \
           LOG_FACADE_ACTIVE LOG_SINK_FD LOG_MIN_LEVEL _log_sink_ready
  do
    unset "$_v"
  done
}

# --------------------------------------------------------------------------
# Source facade in wrapper context
# --------------------------------------------------------------------------
reset_facade_state

JOB_WRAP_ACTIVE=1
export JOB_WRAP_ACTIVE

LOG_LIB_DIR="$_sandbox_lib"
export LOG_LIB_DIR

# shellcheck disable=SC1090
. "$_sandbox_lib/log.sh" 1>&2 || {
  echo "ERROR: failed to source log.sh" >&2
  exit 2
}

# --------------------------------------------------------------------------
# TEST 1: happy path init + write + close + latest link behavior
# --------------------------------------------------------------------------
JOB="unit"
JOB_LOG_DIR="$_sandbox_logs/$JOB"
mkdir -p "$JOB_LOG_DIR" || exit 2
LOG_FILE="$JOB_LOG_DIR/${JOB}-2026-01-17-000001.log"

log_init "$JOB" "$LOG_FILE" INFO 1>/dev/null 2>&1
rc=$?
assert_eq "$rc" "0" "log_init returns 0 on happy path"

assert_exists "$LOG_FILE" "log file created"

log_info "hello" 1>/dev/null 2>&1
rc=$?
assert_eq "$rc" "0" "log_info returns 0 when written"

log_close 1>/dev/null 2>&1
rc=$?
assert_eq "$rc" "0" "log_close returns 0"

assert_file_contains "$LOG_FILE" "[local] INFO hello" "log line contains level and message"
# Behavior-based check: latest path resolves to current log contents (also implies it exists)
assert_file_contains "$_sandbox_logs/${JOB}-latest.log" "[local] INFO hello" "latest symlink resolves to current log"

# --------------------------------------------------------------------------
# TEST 2: level gating
# --------------------------------------------------------------------------
reset_facade_state
JOB_WRAP_ACTIVE=1
export JOB_WRAP_ACTIVE
LOG_LIB_DIR="$_sandbox_lib"
export LOG_LIB_DIR
# shellcheck disable=SC1090
. "$_sandbox_lib/log.sh" 1>&2 || { echo "ERROR: failed to re-source log.sh" >&2; exit 2; }

LOG_FILE2="$_sandbox_logs/${JOB}-2026-01-17-000002.log"
log_init "$JOB" "$LOG_FILE2" WARN 1>/dev/null 2>&1
rc=$?
assert_eq "$rc" "0" "log_init with MIN_LEVEL=WARN returns 0"

log_info "should_suppress" 1>/dev/null 2>&1
rc=$?
assert_eq "$rc" "4" "log_info returns 4 when suppressed by policy"

log_warn "should_log" 1>/dev/null 2>&1
rc=$?
assert_eq "$rc" "0" "log_warn returns 0 when allowed"

log_close 1>/dev/null 2>&1

assert_file_not_contains "$LOG_FILE2" "should_suppress" "suppressed message not written"
assert_file_contains "$LOG_FILE2" "[local] WARN should_log" "allowed message written"

# --------------------------------------------------------------------------
# TEST 3: sanitize (CR strip, non-ASCII -> '?')
# --------------------------------------------------------------------------
reset_facade_state
JOB_WRAP_ACTIVE=1
export JOB_WRAP_ACTIVE
LOG_LIB_DIR="$_sandbox_lib"
export LOG_LIB_DIR
# shellcheck disable=SC1090
. "$_sandbox_lib/log.sh" 1>&2 || { echo "ERROR: failed to re-source log.sh" >&2; exit 2; }

LOG_FILE3="$_sandbox_logs/${JOB}-2026-01-17-000003.log"
log_init "$JOB" "$LOG_FILE3" DEBUG 1>/dev/null 2>&1
rc=$?
assert_eq "$rc" "0" "log_init DEBUG returns 0"

# Build a message that includes CR and a non-ASCII byte.
# Insert a literal CR via printf; insert a non-ASCII byte via octal escape.
_msg=$(printf 'a\rb \200')
log_info "$_msg" 1>/dev/null 2>&1
rc=$?
assert_eq "$rc" "0" "log_info returns 0 for sanitizable message"

log_close 1>/dev/null 2>&1

# After sanitize: CR removed, 0x80 -> '?'
assert_file_contains "$LOG_FILE3" "[local] INFO ab ?" "sanitize: CR stripped and non-ASCII replaced"

# --------------------------------------------------------------------------
# TEST 4: log_capture (two lines) + CRLF handling + missing trailing newline
# --------------------------------------------------------------------------
reset_facade_state
JOB_WRAP_ACTIVE=1
export JOB_WRAP_ACTIVE
LOG_LIB_DIR="$_sandbox_lib"
export LOG_LIB_DIR
# shellcheck disable=SC1090
. "$_sandbox_lib/log.sh" 1>&2 || { echo "ERROR: failed to re-source log.sh" >&2; exit 2; }

LOG_FILE4="$_sandbox_logs/${JOB}-2026-01-17-000004.log"
log_init "$JOB" "$LOG_FILE4" INFO 1>/dev/null 2>&1
rc=$?
assert_eq "$rc" "0" "log_init for capture returns 0"

printf 'line1\nline2\n' | log_capture INFO 1>/dev/null 2>&1
rc=$?
assert_eq "$rc" "0" "log_capture returns 0"

# CRLF input should have CR stripped by sanitizer
printf 'crlf1\r\ncrlf2\r\n' | log_capture INFO 1>/dev/null 2>&1
rc=$?
assert_eq "$rc" "0" "log_capture returns 0 for CRLF input"

# No trailing newline: should still log that final line
printf 'no_newline' | log_capture INFO 1>/dev/null 2>&1
rc=$?
assert_eq "$rc" "0" "log_capture returns 0 for input without trailing newline"

log_close 1>/dev/null 2>&1

assert_file_contains "$LOG_FILE4" "[local] INFO line1" "capture wrote line1"
assert_file_contains "$LOG_FILE4" "[local] INFO line2" "capture wrote line2"
assert_file_contains "$LOG_FILE4" "[local] INFO crlf1" "capture wrote crlf1 (CR stripped)"
assert_file_contains "$LOG_FILE4" "[local] INFO crlf2" "capture wrote crlf2 (CR stripped)"
assert_file_contains "$LOG_FILE4" "[local] INFO no_newline" "capture wrote final line without trailing newline"

# --------------------------------------------------------------------------
# TEST 5: retention pruning (keep last 2)
# --------------------------------------------------------------------------
reset_facade_state
JOB_WRAP_ACTIVE=1
export JOB_WRAP_ACTIVE
LOG_LIB_DIR="$_sandbox_lib"
export LOG_LIB_DIR
# shellcheck disable=SC1090
. "$_sandbox_lib/log.sh" 1>&2 || { echo "ERROR: failed to re-source log.sh" >&2; exit 2; }

JOB2="ret"
LOG_DIR="$_sandbox_logs/ret"
mkdir -p "$LOG_DIR" || exit 2

# Pre-seed 3 old logs in the same directory.
# Names must match <JOB>-YYYY-MM-DD-HHMMSS.log
_old1="$LOG_DIR/${JOB2}-2026-01-17-000010.log"
_old2="$LOG_DIR/${JOB2}-2026-01-17-000011.log"
_old3="$LOG_DIR/${JOB2}-2026-01-17-000012.log"
: > "$_old1"; : > "$_old2"; : > "$_old3"

LOG_KEEP_COUNT=2
export LOG_KEEP_COUNT

_new="$LOG_DIR/${JOB2}-2026-01-17-000013.log"
log_init "$JOB2" "$_new" INFO 1>/dev/null 2>&1
rc=$?
assert_eq "$rc" "0" "log_init with retention returns 0"

log_info "fresh" 1>/dev/null 2>&1
log_close 1>/dev/null 2>&1

# Keep count is total-per-job, including the current run.
# With 4 logs total and keep=2, the two newest should remain:
#   ret-2026-01-17-000012.log (newer existing)
#   ret-2026-01-17-000013.log (current)
assert_not_exists "$_old1" "retention deleted oldest log"
assert_not_exists "$_old2" "retention deleted second-oldest log"
assert_exists "$_old3" "retention kept newest preexisting log"
assert_exists "$_new"  "retention kept current log"

# --------------------------------------------------------------------------
# TEST 6: misuse (no wrapper context)
# --------------------------------------------------------------------------
reset_facade_state

unset JOB_WRAP_ACTIVE
export LOG_LIB_DIR

# shellcheck disable=SC1090
. "$_sandbox_lib/log.sh" 1>&2 || {
  echo "ERROR: failed to source log.sh (second time)" >&2
  exit 2
}

LOG_FILE5="$_sandbox_logs/${JOB}-2026-01-17-000005.log"
log_init "$JOB" "$LOG_FILE5" INFO 1>/dev/null 2>&1
rc=$?
assert_eq "$rc" "11" "log_init returns 11 when JOB_WRAP_ACTIVE is missing"

# --------------------------------------------------------------------------
# TEST 7: invalid JOB_NAME rejected by sink validation
# --------------------------------------------------------------------------
reset_facade_state
JOB_WRAP_ACTIVE=1
export JOB_WRAP_ACTIVE
LOG_LIB_DIR="$_sandbox_lib"
export LOG_LIB_DIR
# shellcheck disable=SC1090
. "$_sandbox_lib/log.sh" 1>&2 || { echo "ERROR: failed to re-source log.sh" >&2; exit 2; }

_bad_job="bad/job"
_bad_log="$_sandbox_logs/bad/${_bad_job}-2026-01-17-000006.log"
log_init "$_bad_job" "$_bad_log" INFO 1>/dev/null 2>&1
rc=$?
assert_eq "$rc" "11" "log_init returns 11 for invalid JOB_NAME"

# --------------------------------------------------------------------------
# TEST 8: invalid LOG_FILE basename rejected (does not match <JOB>-YYYY-MM-DD-HHMMSS.log)
# --------------------------------------------------------------------------
reset_facade_state
JOB_WRAP_ACTIVE=1
export JOB_WRAP_ACTIVE
LOG_LIB_DIR="$_sandbox_lib"
export LOG_LIB_DIR
# shellcheck disable=SC1090
. "$_sandbox_lib/log.sh" 1>&2 || { echo "ERROR: failed to re-source log.sh" >&2; exit 2; }

_bad_job2="unit"
_bad_log2="$_sandbox_logs/${_bad_job2}-NOT_A_TIMESTAMP.log"
log_init "$_bad_job2" "$_bad_log2" INFO 1>/dev/null 2>&1
rc=$?
assert_eq "$rc" "11" "log_init returns 11 for invalid LOG_FILE basename"

# --------------------------------------------------------------------------
# TEST 9: unwritable log directory returns operational failure (nonzero; expected 10)
# --------------------------------------------------------------------------
reset_facade_state
JOB_WRAP_ACTIVE=1
export JOB_WRAP_ACTIVE
LOG_LIB_DIR="$_sandbox_lib"
export LOG_LIB_DIR
# shellcheck disable=SC1090
. "$_sandbox_lib/log.sh" 1>&2 || { echo "ERROR: failed to re-source log.sh" >&2; exit 2; }

_ro_dir="$_sandbox_logs/ro"
mkdir -p "$_ro_dir" || exit 2
chmod 500 "$_ro_dir" 2>/dev/null || :

_ro_log="$_ro_dir/rojob-2026-01-17-000007.log"
log_init "rojob" "$_ro_log" INFO 1>/dev/null 2>&1
rc=$?
# log-sink uses rc=10 for cannot open log file / cannot update symlink
assert_eq "$rc" "10" "log_init returns 10 when log file cannot be opened (unwritable dir)"

# Restore perms for cleanup friendliness
chmod 700 "$_ro_dir" 2>/dev/null || :

# --------------------------------------------------------------------------
# TEST 10: calling log_info before log_init should fail (children not sourced)
# --------------------------------------------------------------------------
reset_facade_state
JOB_WRAP_ACTIVE=1
export JOB_WRAP_ACTIVE
LOG_LIB_DIR="$_sandbox_lib"
export LOG_LIB_DIR
# shellcheck disable=SC1090
. "$_sandbox_lib/log.sh" 1>&2 || { echo "ERROR: failed to re-source log.sh" >&2; exit 2; }

log_info "preinit" 1>/dev/null 2>&1
rc=$?
assert_nonzero "$rc" "log_info before log_init returns nonzero"

# --------------------------------------------------------------------------
# TEST 11: log_close idempotent-ish (close twice returns 0)
# --------------------------------------------------------------------------
reset_facade_state
JOB_WRAP_ACTIVE=1
export JOB_WRAP_ACTIVE
LOG_LIB_DIR="$_sandbox_lib"
export LOG_LIB_DIR
# shellcheck disable=SC1090
. "$_sandbox_lib/log.sh" 1>&2 || { echo "ERROR: failed to re-source log.sh" >&2; exit 2; }

LOG_FILE6="$_sandbox_logs/${JOB}-2026-01-17-000008.log"
log_init "$JOB" "$LOG_FILE6" INFO 1>/dev/null 2>&1
rc=$?
assert_eq "$rc" "0" "log_init for double-close returns 0"

log_close 1>/dev/null 2>&1
rc=$?
assert_eq "$rc" "0" "first log_close returns 0"

log_close 1>/dev/null 2>&1
rc=$?
assert_eq "$rc" "0" "second log_close returns 0"

# --------------------------------------------------------------------------
# TEST 12: missing datetime.sh in LOG_LIB_DIR causes operational failure (rc=10)
# --------------------------------------------------------------------------
reset_facade_state
JOB_WRAP_ACTIVE=1
export JOB_WRAP_ACTIVE

_lib_nodt="$_sandbox/lib-nodt"
mkdir -p "$_lib_nodt" || exit 2
cp "$_sandbox_lib/log.sh" "$_lib_nodt/log.sh" || exit 2
cp "$_sandbox_lib/log-format.sh" "$_lib_nodt/log-format.sh" || exit 2
cp "$_sandbox_lib/log-sink.sh" "$_lib_nodt/log-sink.sh" || exit 2
cp "$_sandbox_lib/log-capture.sh" "$_lib_nodt/log-capture.sh" || exit 2
# Intentionally omit datetime.sh

LOG_LIB_DIR="$_lib_nodt"
export LOG_LIB_DIR

# shellcheck disable=SC1090
. "$_lib_nodt/log.sh" 1>&2 || { echo "ERROR: failed to source log.sh (nodt)" >&2; exit 2; }

LOG_FILE7="$_sandbox_logs/${JOB}-2026-01-17-000009.log"
log_init "$JOB" "$LOG_FILE7" INFO 1>/dev/null 2>&1
rc=$?
assert_eq "$rc" "10" "log_init returns 10 when datetime.sh cannot be sourced"

# Summary
if [ "$_fail" -eq 0 ]; then
  say "# PASS"
  exit 0
fi
say "# FAIL"
exit 1
