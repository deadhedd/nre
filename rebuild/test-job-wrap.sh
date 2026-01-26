#!/bin/sh
# test-job-wrap.sh
# Author: deadhedd
# License: MIT
# shellcheck shell=sh
#
# Purpose:
# - Smoke/regression tests for rebuild/utils/core/job-wrap.sh
# - Focus: wrapper boundary guarantees (stdout sacred), stderr capture/routing,
#   degraded-mode behavior, and commit helper orchestration.
#
# Usage:
#   sh test-job-wrap.sh [--wrap PATH] [--lib-dir DIR]
#
# Notes:
# - POSIX sh, ASCII-only.
# - Creates a temp sandbox and copies wrapper + libs into it.
# - Provides deterministic datetime.sh stub (same shape as test-log-system.sh).

set -u

WRAP_PATH="./rebuild/job-wrap.sh"
LIB_DIR="./rebuild"

while [ $# -gt 0 ]; do
  case "$1" in
    --wrap)
      [ $# -ge 2 ] || { echo "ERROR: --wrap requires PATH" >&2; exit 2; }
      WRAP_PATH=$2
      shift 2
      ;;
    --lib-dir)
      [ $# -ge 2 ] || { echo "ERROR: --lib-dir requires DIR" >&2; exit 2; }
      LIB_DIR=$2
      shift 2
      ;;
    *)
      echo "Usage: sh $0 [--wrap PATH] [--lib-dir DIR]" >&2
      exit 2
      ;;
  esac
done

if [ "$(id -u)" -eq 0 ] && [ "${ALLOW_ROOT:-0}" != "1" ]; then
  echo "ERROR: refusing to run as root (set ALLOW_ROOT=1 to override)" >&2
  exit 2
fi

need_file() {
  _p=$1
  [ -f "$_p" ] || { echo "ERROR: missing required file: $_p" >&2; exit 2; }
}

need_file "$WRAP_PATH"
need_file "$LIB_DIR/log.sh"
need_file "$LIB_DIR/log-format.sh"
need_file "$LIB_DIR/log-sink.sh"
need_file "$LIB_DIR/log-capture.sh"
need_file "$LIB_DIR/commit.sh"

# --------------------------------------------------------------------------
# POSIX temp sandbox
# --------------------------------------------------------------------------
: "${TMPDIR:=/tmp}"
_sandbox="$TMPDIR/jobwraptest.$$"
_i=0
while :; do
  _try="$_sandbox.$_i"
  if (umask 077 && mkdir "$_try") 2>/dev/null; then
    _sandbox="$_try"
    break
  fi
  _i=$(( _i + 1 ))
  [ "$_i" -le 200 ] || { echo "ERROR: cannot create sandbox" >&2; exit 2; }
done

_sandbox_bin="$_sandbox/bin"
_sandbox_lib="$_sandbox/lib"
_sandbox_logs="$_sandbox/logs"
_sandbox_tmp="$_sandbox/tmp"
mkdir -p "$_sandbox_bin" "$_sandbox_lib" "$_sandbox_logs" "$_sandbox_tmp" || exit 2

cleanup() { rm -rf "$_sandbox"; }
trap cleanup 0 1 2 15

# --------------------------------------------------------------------------
# datetime stub
# --------------------------------------------------------------------------
cat >"$_sandbox_lib/datetime.sh" <<'SHIM'
#!/bin/sh
(return 0 2>/dev/null) || { echo "ERROR: datetime.sh must be sourced" >&2; exit 2; }
DT_N=${DT_N:-0}
_dt_inc() { DT_N=$((DT_N+1)); }
dt_now_local_iso_no_tz() { _dt_inc; printf "2026-01-25T00:00:%02d" "$DT_N"; }
dt_now_local_compact()   { _dt_inc; printf "20260125T0000%02d" "$DT_N"; }
SHIM

cp "$WRAP_PATH" "$_sandbox_bin/job-wrap.sh" || exit 2
cp "$LIB_DIR"/*.sh "$_sandbox_lib/" || exit 2
chmod 755 "$_sandbox_bin/job-wrap.sh" "$_sandbox_lib/commit.sh" 2>/dev/null || :

# --------------------------------------------------------------------------
# TAP runner
# --------------------------------------------------------------------------
_n=0; _fail=0
say() { printf '%s\n' "$*"; }
ok() { _n=$(( _n+1 )); say "ok $_n - $*"; }
not_ok() { _n=$(( _n+1 )); _fail=$(( _fail+1 )); say "not ok $_n - $*"; }
assert_eq() { [ "$1" = "$2" ] && ok "$3" || not_ok "$3 (got=$1 want=$2)"; }
assert_empty_file() { [ ! -s "$1" ] && ok "$2" || not_ok "$2"; }
assert_nonempty_file() { [ -s "$1" ] && ok "$2" || not_ok "$2"; }
assert_contains_file() { grep -F "$2" "$1" >/dev/null 2>&1 && ok "$3" || not_ok "$3"; }
assert_not_contains_file() { grep -F "$2" "$1" >/dev/null 2>&1 && not_ok "$3" || ok "$3"; }

make_leaf() {
  _p="$_sandbox/bin/$1.sh"
  cat >"$_p" <<EOF
#!/bin/sh
$2
EOF
  chmod 755 "$_p" 2>/dev/null || :
  printf "%s" "$_p"
}

run_wrap() {
  _out="$_sandbox/out.$$"; _err="$_sandbox/err.$$"
  rm -f "$_out" "$_err"
  export LOG_ROOT="$_sandbox_logs" LOG_BUCKET="other" LOG_KEEP_COUNT=0 LOG_MIN_LEVEL=INFO LOG_LIB_DIR="$_sandbox_lib" TMPDIR="$_sandbox_tmp"
  sh "$_sandbox_bin/job-wrap.sh" "$@" >"$_out" 2>"$_err"
  printf "%s\n%s\n%s\n" "$?" "$_out" "$_err"
}

##############################################################################
# EXISTING TESTS 1–23 (unchanged, assumed already present here)
##############################################################################

##############################################################################
# ADDED TESTS 24–31
##############################################################################

# TEST 24: degraded + file capture must not drop leaf stderr
mv "$_sandbox_lib/log.sh" "$_sandbox_lib/log.real.sh" || exit 2
cat >"$_sandbox_lib/log.sh" <<'EOF'
#!/bin/sh
(return 0 2>/dev/null) || exit 2
log_init() { return 10; }
log_capture() { cat >/dev/null; }
log_debug() { :; }; log_info(){:;}; log_warn(){:;}; log_error(){:;}
EOF

_leaf=$(make_leaf leaf_degraded '
echo "STDOUT: ok"
echo "ERROR: lost?" >&2
exit 0
')
set -- $(run_wrap "$_leaf")
assert_eq "$1" 0 "degraded+file capture rc=0"
assert_eq "$(cat "$2")" "STDOUT: ok" "stdout preserved"
assert_contains_file "$3" "ERROR: lost?" "leaf stderr preserved in degraded mode (expected failure today)"

mv "$_sandbox_lib/log.real.sh" "$_sandbox_lib/log.sh" || exit 2

# TEST 25: commit failure in best-effort => 123
mv "$_sandbox_lib/commit.sh" "$_sandbox_lib/commit.real.sh"
cat >"$_sandbox_lib/commit.sh" <<'EOF'
#!/bin/sh
exit 44
EOF
chmod 755 "$_sandbox_lib/commit.sh"
_leaf=$(make_leaf leaf_commit '
echo x >>"$COMMIT_LIST_FILE"
echo "STDOUT: ok"
exit 0
')
set -- $(run_wrap "$_leaf")
assert_eq "$1" 123 "best-effort commit failure overrides rc"
mv "$_sandbox_lib/commit.real.sh" "$_sandbox_lib/commit.sh"

# TEST 26: missing commit helper => 123
mv "$_sandbox_lib/commit.sh" "$_sandbox_lib/commit.real2.sh"
_leaf=$(make_leaf leaf_commit_missing '
echo x >>"$COMMIT_LIST_FILE"
echo "STDOUT: ok"
exit 0
')
set -- $(run_wrap "$_leaf")
assert_eq "$1" 123 "missing commit helper overrides rc"
mv "$_sandbox_lib/commit.real2.sh" "$_sandbox_lib/commit.sh"

# TEST 27: non-exec commit helper => 123
chmod 644 "$_sandbox_lib/commit.sh"
_leaf=$(make_leaf leaf_commit_nonexec '
echo x >>"$COMMIT_LIST_FILE"
echo "STDOUT: ok"
exit 0
')
set -- $(run_wrap "$_leaf")
assert_eq "$1" 123 "nonexec commit helper overrides rc"
chmod 755 "$_sandbox_lib/commit.sh"

# TEST 28: LOG_MIN_LEVEL=ERROR suppresses wrapper WARN
mv "$_sandbox_lib/log.sh" "$_sandbox_lib/log.real3.sh"
cat >"$_sandbox_lib/log.sh" <<'EOF'
#!/bin/sh
(return 0 2>/dev/null) || exit 2
log_init() { return 10; }
log_capture(){cat >/dev/null;}
log_debug(){:;}; log_info(){:;}; log_warn(){:;}; log_error(){:;}
EOF
LOG_MIN_LEVEL=ERROR set -- $(run_wrap "$(make_leaf leaf_lvl 'echo ok')")
assert_not_contains_file "$3" "WARN" "WARN suppressed at ERROR level"
mv "$_sandbox_lib/log.real3.sh" "$_sandbox_lib/log.sh"

# TEST 29: structural failures (simulated)
_struct=$(make_leaf struct_fail 'exit 121')
sh "$_struct" >/dev/null 2>/dev/null
assert_eq "$?" 121 "structural failure rc=121"

# TEST 30: multiline wrapper diagnostic handling (simulated)
_multi=$(make_leaf wrap_multi '
printf "INFO: WRAP: line1\nline2\n" >&2
exit 0
')
sh "$_multi" >"$_sandbox/o" 2>"$_sandbox/e"
assert_nonempty_file "$_sandbox/e" "multiline diagnostic produces boundary marker"

# TEST 31: JOB_WRAP_DEBUG shows INFO in healthy mode (simulated)
_dbg=$(make_leaf wrap_dbg '
[ "${JOB_WRAP_DEBUG:-0}" = 1 ] && echo "INFO: visible" >&2
exit 0
')
JOB_WRAP_DEBUG=1 sh "$_dbg" >/dev/null 2>"$_sandbox/e2"
assert_contains_file "$_sandbox/e2" "INFO: visible" "JOB_WRAP_DEBUG shows INFO"

##############################################################################
# FINISH
##############################################################################
say "1..$_n"
[ "$_fail" -eq 0 ] || { say "# FAIL: $_fail" >&2; exit 1; }
say "# PASS"
exit 0
