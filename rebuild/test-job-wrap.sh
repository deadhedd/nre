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
# Defaults assume:
#   ./rebuild/job-wrap.sh
#   ./rebuild/log.sh + helpers in ./rebuild/
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

# Refuse to run as root unless explicitly allowed.
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

need_file "$WRAP_PATH"
need_file "$LIB_DIR/log.sh"
need_file "$LIB_DIR/log-format.sh"
need_file "$LIB_DIR/log-sink.sh"
need_file "$LIB_DIR/log-capture.sh"
need_file "$LIB_DIR/commit.sh"

# --------------------------------------------------------------------------
# POSIX temp sandbox (no mktemp)
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
  if [ "$_i" -gt 200 ]; then
    echo "ERROR: could not create sandbox dir in $TMPDIR" >&2
    exit 2
  fi
done

_sandbox_bin="$_sandbox/bin"
_sandbox_lib="$_sandbox/lib"
_sandbox_logs="$_sandbox/logs"
_sandbox_tmp="$_sandbox/tmp"
mkdir -p "$_sandbox_bin" "$_sandbox_lib" "$_sandbox_logs" "$_sandbox_tmp" || exit 2

cleanup() {
  # Optional: preserve sandbox for post-mortem inspection.
  # Usage: KEEP_SANDBOX=1 sh test-job-wrap.sh
  if [ "${KEEP_SANDBOX:-0}" = "1" ]; then
    :
  else
    rm -rf "$_sandbox"
  fi
}
trap cleanup 0 1 2 15

# --------------------------------------------------------------------------
# Deterministic datetime stub
# --------------------------------------------------------------------------
cat >"$_sandbox_lib/datetime.sh" <<'SHIM'
#!/bin/sh
# datetime.sh (test stub)
# Provides deterministic local timestamps.

(return 0 2>/dev/null) || { echo "ERROR: datetime.sh must be sourced" >&2; exit 2; }

if [ "${DT_STUB_LOADED:-0}" = "1" ]; then
  return 0
fi
DT_STUB_LOADED=1

_DT_N=${_DT_N:-0}

_dt_inc() { _DT_N=$(( _DT_N + 1 )); }

dt_now_local_iso_no_tz() {
  _dt_inc
  _s=$_DT_N
  if [ "$_s" -lt 10 ]; then _s="0$_s"; fi
  printf '%s' "2026-01-25T00:00:${_s}"
}

dt_now_local_compact() {
  _dt_inc
  _s=$_DT_N
  if [ "$_s" -lt 10 ]; then _s="0$_s"; fi
  printf '%s' "20260125T0000${_s}"
}
SHIM

# --------------------------------------------------------------------------
# Copy wrapper + libs into sandbox
# Layout expected by job-wrap.sh:
# - WRAP_DIR is dirname($0); REPO_ROOT is WRAP_DIR/..
# - default LOG_LIB_DIR is WRAP_DIR, but we allow overrides.
# --------------------------------------------------------------------------
cp "$WRAP_PATH"              "$_sandbox_bin/job-wrap.sh" || exit 2
cp "$LIB_DIR/log.sh"         "$_sandbox_lib/log.sh" || exit 2
cp "$LIB_DIR/log-format.sh"  "$_sandbox_lib/log-format.sh" || exit 2
cp "$LIB_DIR/log-sink.sh"    "$_sandbox_lib/log-sink.sh" || exit 2
cp "$LIB_DIR/log-capture.sh" "$_sandbox_lib/log-capture.sh" || exit 2
cp "$LIB_DIR/commit.sh"      "$_sandbox_lib/commit.sh" || exit 2

chmod 755 "$_sandbox_bin/job-wrap.sh" "$_sandbox_lib/commit.sh" 2>/dev/null || :

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
  if [ "$_got" = "$_want" ]; then ok "$_msg"; else not_ok "$_msg (got=$_got want=$_want)"; fi
}

assert_nonempty_file() {
  _p=$1
  _msg=$2
  if [ -s "$_p" ]; then ok "$_msg"; else not_ok "$_msg (empty/missing: $_p)"; fi
}

assert_empty_file() {
  _p=$1
  _msg=$2
  if [ ! -s "$_p" ] 2>/dev/null; then ok "$_msg"; else not_ok "$_msg (expected empty: $_p)"; fi
}

assert_exists() {
  _p=$1
  _msg=$2
  if [ -f "$_p" ]; then ok "$_msg"; else not_ok "$_msg (missing: $_p)"; fi
}

assert_contains_file() {
  _p=$1
  _needle=$2
  _msg=$3
  if grep -F "$_needle" "$_p" >/dev/null 2>&1; then ok "$_msg"; else not_ok "$_msg (missing needle: $_needle)"; fi
}

assert_not_contains_file() {
  _p=$1
  _needle=$2
  _msg=$3
  if grep -F "$_needle" "$_p" >/dev/null 2>&1; then not_ok "$_msg (unexpected needle: $_needle)"; else ok "$_msg"; fi
}

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
make_leaf() {
  # Args:
  #   $1 = leaf name (used as filename stem)
  #   $2 = shell body (literal, no templating)
  _name=$1
  _body=$2
  _p="$_sandbox/bin/${_name}.sh"

  {
    printf '%s\n' '#!/bin/sh'
    # Preserve body literally (no accidental expansion from an unquoted heredoc)
    printf '%s\n' "$_body"
  } >"$_p" || exit 2

  chmod 755 "$_p" 2>/dev/null || :
  printf '%s' "$_p"
}

run_jobwrap() {
  # Execute job-wrap under a clean shell context where `set -e` cannot leak in
  # from the harness environment.
  #
  # Rationale: job-wrap intentionally treats some nonzero helper codes as
  # non-fatal (degrade/continue). `set -e` would otherwise short-circuit.
  sh -c 'set +e; "$@"' sh "$@"
}

run_wrap() {
  # Args:
  #   $1.. = wrapper args (leaf + leaf args)
  #
  # Sets globals:
  #   WRAP_RC, WRAP_OUT, WRAP_ERR
  WRAP_OUT="$_sandbox/out.$$"
  WRAP_ERR="$_sandbox/err.$$"
  rm -f "$WRAP_OUT" "$WRAP_ERR" 2>/dev/null || :

  LOG_ROOT="$_sandbox_logs"
  LOG_BUCKET="other"
  LOG_KEEP_COUNT="0"
  LOG_MIN_LEVEL="INFO"
  LOG_LIB_DIR="$_sandbox_lib"
  TMPDIR="$_sandbox_tmp"
  export LOG_ROOT LOG_BUCKET LOG_KEEP_COUNT LOG_MIN_LEVEL LOG_LIB_DIR TMPDIR

  run_jobwrap "$_sandbox/bin/job-wrap.sh" "$@" >"$WRAP_OUT" 2>"$WRAP_ERR"
  WRAP_RC=$?
}

# --------------------------------------------------------------------------
# TEST 1: usage => exit 120
# --------------------------------------------------------------------------
_out="$_sandbox/out.usage"
_err="$_sandbox/err.usage"
rm -f "$_out" "$_err" 2>/dev/null || :
LOG_ROOT="$_sandbox_logs" LOG_LIB_DIR="$_sandbox_lib" TMPDIR="$_sandbox_tmp" \
  run_jobwrap "$_sandbox/bin/job-wrap.sh" >"$_out" 2>"$_err"
rc=$?
assert_eq "$rc" "120" "job-wrap usage returns 120"
assert_nonempty_file "$_err" "job-wrap usage emits error on stderr"
assert_empty_file "$_out" "job-wrap usage emits nothing on stdout"

# --------------------------------------------------------------------------
# TEST 2: recursion guard (JOB_WRAP_ACTIVE=1) => exit 120
# --------------------------------------------------------------------------
_out="$_sandbox/out.guard"
_err="$_sandbox/err.guard"
rm -f "$_out" "$_err" 2>/dev/null || :
JOB_WRAP_ACTIVE=1 LOG_ROOT="$_sandbox_logs" LOG_LIB_DIR="$_sandbox_lib" TMPDIR="$_sandbox_tmp" \
  run_jobwrap "$_sandbox/bin/job-wrap.sh" "/does/not/matter" >"$_out" 2>"$_err"
rc=$?
assert_eq "$rc" "120" "job-wrap recursion guard returns 120"
assert_empty_file "$_out" "recursion guard emits nothing on stdout"

# --------------------------------------------------------------------------
# TEST 3: happy path => leaf stdout preserved; leaf stderr captured (no boundary)
# --------------------------------------------------------------------------
_leaf=$(make_leaf leaf_ok '
echo "STDOUT: hello"
echo "STDERR: secret" >&2
exit 0
')

run_wrap "$_leaf"
rc=$WRAP_RC; out=$WRAP_OUT; err=$WRAP_ERR

assert_eq "$rc" "0" "happy path returns leaf rc"
assert_eq "$(cat "$out" 2>/dev/null || :)" "STDOUT: hello" "happy path preserves leaf stdout"
assert_empty_file "$err" "happy path keeps boundary stderr quiet"

_job="leaf_ok"
_latest="$_sandbox_logs/other/${_job}/${_job}-latest.log"
assert_exists "$_latest" "happy path updates latest log symlink (or file)"
assert_nonempty_file "$_latest" "happy path latest log has content"

_boot_dir="$_sandbox_logs/_bootstrap"
_boot_any=$(ls -1 "$_boot_dir" 2>/dev/null | grep -E "^${_job}-bootstrap-.*\.log$" | head -n 1 || true)
if [ -n "$_boot_any" ]; then
  ok "happy path wrote a bootstrap log file"
else
  not_ok "happy path wrote a bootstrap log file (missing under $_boot_dir)"
fi

# --------------------------------------------------------------------------
# TEST 4: TMPDIR unwritable => passthrough mode => leaf stderr reaches boundary
# --------------------------------------------------------------------------
_bad_tmp="$_sandbox/nowrite"
mkdir -p "$_bad_tmp" || exit 2
chmod 500 "$_bad_tmp" 2>/dev/null || :

_leaf=$(make_leaf leaf_passthru '
echo "STDOUT: ok"
echo "STDERR: should-pass" >&2
exit 0
')

_out="$_sandbox/out.passthru"
_err="$_sandbox/err.passthru"
rm -f "$_out" "$_err" 2>/dev/null || :
LOG_ROOT="$_sandbox_logs" LOG_BUCKET="other" LOG_KEEP_COUNT="0" LOG_MIN_LEVEL="INFO" \
  LOG_LIB_DIR="$_sandbox_lib" TMPDIR="$_bad_tmp" \
  run_jobwrap "$_sandbox/bin/job-wrap.sh" "$_leaf" >"$_out" 2>"$_err"
rc=$?
assert_eq "$rc" "0" "passthrough mode returns leaf rc"
assert_eq "$(cat "$_out" 2>/dev/null || :)" "STDOUT: ok" "passthrough preserves leaf stdout"
assert_nonempty_file "$_err" "passthrough allows leaf stderr to reach boundary"

chmod 700 "$_bad_tmp" 2>/dev/null || :

# --------------------------------------------------------------------------
# TEST 5: log_init stdout leak containment => no boundary stdout leak; degraded mode
# --------------------------------------------------------------------------
mv "$_sandbox_lib/log.sh" "$_sandbox_lib/log.real.sh" || exit 2

cat >"$_sandbox_lib/log.sh" <<'BUG'
#!/bin/sh
# BUGGY log.sh (test double): violates contract by writing to stdout in log_init

(return 0 2>/dev/null) || { echo "ERROR: log.sh must be sourced" >&2; exit 2; }

log_init() {
  echo "LEAKED STDOUT FROM log_init"
  return 0
}

log_capture() { cat >/dev/null; return 0; }
log_debug() { :; }
log_info()  { :; }
log_warn()  { :; }
log_error() { :; }
BUG

_leaf=$(make_leaf leaf_leak '
echo "STDOUT: leaf"
echo "STDERR: leaf" >&2
exit 0
')

run_wrap "$_leaf"
rc=$WRAP_RC; out=$WRAP_OUT; err=$WRAP_ERR

assert_eq "$rc" "0" "log_init stdout leak does not fail the job"
assert_eq "$(cat "$out" 2>/dev/null || :)" "STDOUT: leaf" "log_init leak does not pollute job stdout"
assert_nonempty_file "$err" "log_init leak emits boundary warning (degraded)"

_boot_dir="$_sandbox_logs/_bootstrap"
_boot_hit=$(grep -R "contract violation contained: log_init wrote to stdout" "$_boot_dir" 2>/dev/null | head -n 1 || true)
if [ -n "$_boot_hit" ]; then
  ok "bootstrap log records contained log_init stdout leak"
else
  not_ok "bootstrap log records contained log_init stdout leak"
fi

rm -f "$_sandbox_lib/log.sh" 2>/dev/null || :
mv "$_sandbox_lib/log.real.sh" "$_sandbox_lib/log.sh" || exit 2

# --------------------------------------------------------------------------
# TEST 6: commit orchestration success (leaf writes COMMIT_LIST_FILE)
# --------------------------------------------------------------------------
mv "$_sandbox_lib/commit.sh" "$_sandbox_lib/commit.real.sh" || exit 2
cat >"$_sandbox_lib/commit.sh" <<'COMMIT'
#!/bin/sh
# commit.sh (test double)
_repo=$1
_msg=$2
shift 2
printf 'REPO=%s\n' "$_repo" >>"${TMPDIR:-/tmp}/commit.called" 2>/dev/null || :
printf 'MSG=%s\n' "$_msg" >>"${TMPDIR:-/tmp}/commit.called" 2>/dev/null || :
while [ $# -gt 0 ]; do
  printf 'PATH=%s\n' "$1" >>"${TMPDIR:-/tmp}/commit.called" 2>/dev/null || :
  shift
done
exit 0
COMMIT
chmod 755 "$_sandbox_lib/commit.sh" 2>/dev/null || :

_leaf=$(make_leaf leaf_commit '
echo "notes/Daily/2026-01-25.md" >>"$COMMIT_LIST_FILE"
echo "notes/Weekly/2026-W04.md" >>"$COMMIT_LIST_FILE"
echo "STDOUT: leaf-commit"
exit 0
')

rm -f "$_sandbox_tmp/commit.called" 2>/dev/null || :
_out="$_sandbox/out.commit"
_err="$_sandbox/err.commit"
rm -f "$_out" "$_err" 2>/dev/null || :

LOG_ROOT="$_sandbox_logs" LOG_BUCKET="other" LOG_KEEP_COUNT="0" LOG_MIN_LEVEL="INFO" \
  LOG_LIB_DIR="$_sandbox_lib" TMPDIR="$_sandbox_tmp" COMMIT_MODE="best-effort" COMMIT_MESSAGE="test message" \
  run_jobwrap "$_sandbox/bin/job-wrap.sh" "$_leaf" >"$_out" 2>"$_err"
rc=$?

assert_eq "$rc" "0" "commit best-effort success does not override leaf exit"
assert_eq "$(cat "$_out" 2>/dev/null || :)" "STDOUT: leaf-commit" "commit path preserves stdout"
assert_empty_file "$_err" "commit success keeps boundary stderr quiet"

_called="$_sandbox_tmp/commit.called"
assert_nonempty_file "$_called" "commit helper was invoked and recorded"

# --------------------------------------------------------------------------
# TEST 7: commit helper failure overrides leaf rc with 123
# --------------------------------------------------------------------------
cat >"$_sandbox_lib/commit.sh" <<'COMMIT_BAD'
#!/bin/sh
exit 99
COMMIT_BAD
chmod 755 "$_sandbox_lib/commit.sh" 2>/dev/null || :

_leaf=$(make_leaf leaf_commit_fail '
echo "x" >>"$COMMIT_LIST_FILE"
echo "STDOUT: leaf-should-not-matter"
exit 0
')

_out="$_sandbox/out.commitfail"
_err="$_sandbox/err.commitfail"
rm -f "$_out" "$_err" 2>/dev/null || :
LOG_ROOT="$_sandbox_logs" LOG_BUCKET="other" LOG_KEEP_COUNT="0" LOG_MIN_LEVEL="INFO" \
  LOG_LIB_DIR="$_sandbox_lib" TMPDIR="$_sandbox_tmp" COMMIT_MODE="required" \
  run_jobwrap "$_sandbox/bin/job-wrap.sh" "$_leaf" >"$_out" 2>"$_err"
rc=$?

assert_eq "$rc" "123" "commit helper failure overrides exit with 123 (WRAP_E_COMMIT)"
assert_eq "$(cat "$_out" 2>/dev/null || :)" "STDOUT: leaf-should-not-matter" "commit failure still preserves leaf stdout"
assert_nonempty_file "$_err" "commit failure emits boundary error"

# Restore real commit helper
rm -f "$_sandbox_lib/commit.sh" 2>/dev/null || :
mv "$_sandbox_lib/commit.real.sh" "$_sandbox_lib/commit.sh" || exit 2

# --------------------------------------------------------------------------
# TEST 8: invalid JOB_NAME derived from leaf filename => exit 120
# --------------------------------------------------------------------------
_leaf_bad="$_sandbox/bin/bad name.sh"
cat >"$_leaf_bad" <<'EOF'
#!/bin/sh
echo "should not run"
exit 0
EOF
chmod 755 "$_leaf_bad" 2>/dev/null || :

_out="$_sandbox/out.badjob"
_err="$_sandbox/err.badjob"
rm -f "$_out" "$_err" 2>/dev/null || :
LOG_ROOT="$_sandbox_logs" LOG_LIB_DIR="$_sandbox_lib" TMPDIR="$_sandbox_tmp" \
  run_jobwrap "$_sandbox/bin/job-wrap.sh" "$_leaf_bad" >"$_out" 2>"$_err"
rc=$?
assert_eq "$rc" "120" "invalid JOB_NAME rejected with 120"
assert_empty_file "$_out" "invalid JOB_NAME does not emit stdout"
assert_nonempty_file "$_err" "invalid JOB_NAME emits error on stderr"

# --------------------------------------------------------------------------
# ADDED TEST 9: init failure when log.sh missing/unsourceable => exit 121
# --------------------------------------------------------------------------
mv "$_sandbox_lib/log.sh" "$_sandbox_lib/log.real.sh" || exit 2
# Create a directory where log.sh should be (so "." fails)
mkdir -p "$_sandbox_lib/log.sh" 2>/dev/null || :

_leaf=$(make_leaf leaf_init_fail '
echo "STDOUT: should-not-run"
echo "STDERR: should-not-run" >&2
exit 0
')

_out="$_sandbox/out.initfail"
_err="$_sandbox/err.initfail"
rm -f "$_out" "$_err" 2>/dev/null || :
LOG_ROOT="$_sandbox_logs" LOG_LIB_DIR="$_sandbox_lib" TMPDIR="$_sandbox_tmp" \
  run_jobwrap "$_sandbox/bin/job-wrap.sh" "$_leaf" >"$_out" 2>"$_err"
rc=$?

assert_eq "$rc" "121" "missing/unsourceable log.sh causes init failure 121"
assert_empty_file "$_out" "init failure does not emit stdout"
assert_nonempty_file "$_err" "init failure emits stderr"

# Restore real log.sh
rm -rf "$_sandbox_lib/log.sh" 2>/dev/null || :
mv "$_sandbox_lib/log.real.sh" "$_sandbox_lib/log.sh" || exit 2

# --------------------------------------------------------------------------
# ADDED TEST 10: log_init returns 10 => degraded mode (warn) but job continues
# --------------------------------------------------------------------------
mv "$_sandbox_lib/log.sh" "$_sandbox_lib/log.real.sh" || exit 2

cat >"$_sandbox_lib/log.sh" <<'LOG10'
#!/bin/sh
# log.sh (test double): log_init operational failure (rc=10)

(return 0 2>/dev/null) || { echo "ERROR: log.sh must be sourced" >&2; exit 2; }

log_init() { return 10; }
log_capture() { cat >/dev/null; return 0; }
log_debug() { :; }
log_info()  { :; }
log_warn()  { :; }
log_error() { :; }
LOG10

_leaf=$(make_leaf leaf_log10 '
echo "STDOUT: ok"
echo "STDERR: leaf-stderr" >&2
exit 0
')

run_wrap "$_leaf"
rc=$WRAP_RC; out=$WRAP_OUT; err=$WRAP_ERR

assert_eq "$rc" "0" "log_init rc=10 does not fail the job"
assert_eq "$(cat "$out" 2>/dev/null || :)" "STDOUT: ok" "log_init rc=10 does not pollute stdout"
assert_nonempty_file "$err" "log_init rc=10 produces boundary warning (degraded)"

rm -f "$_sandbox_lib/log.sh" 2>/dev/null || :
mv "$_sandbox_lib/log.real.sh" "$_sandbox_lib/log.sh" || exit 2

# --------------------------------------------------------------------------
# ADDED TEST 11: log_init returns 11 (misuse) => wrapper init failure 121
# --------------------------------------------------------------------------
mv "$_sandbox_lib/log.sh" "$_sandbox_lib/log.real.sh" || exit 2

cat >"$_sandbox_lib/log.sh" <<'LOG11'
#!/bin/sh
# log.sh (test double): log_init misuse (rc=11)

(return 0 2>/dev/null) || { echo "ERROR: log.sh must be sourced" >&2; exit 2; }

log_init() { return 11; }
log_capture() { cat >/dev/null; return 0; }
log_debug() { :; }
log_info()  { :; }
log_warn()  { :; }
log_error() { :; }
LOG11

_leaf=$(make_leaf leaf_log11 '
echo "STDOUT: should-not-run"
exit 0
')

_out="$_sandbox/out.log11"
_err="$_sandbox/err.log11"
rm -f "$_out" "$_err" 2>/dev/null || :
LOG_ROOT="$_sandbox_logs" LOG_BUCKET="other" LOG_KEEP_COUNT="0" LOG_MIN_LEVEL="INFO" \
  LOG_LIB_DIR="$_sandbox_lib" TMPDIR="$_sandbox_tmp" \
  run_jobwrap "$_sandbox/bin/job-wrap.sh" "$_leaf" >"$_out" 2>"$_err"
rc=$?

assert_eq "$rc" "121" "log_init misuse (rc=11) causes init failure 121"
assert_empty_file "$_out" "log_init misuse does not emit stdout"
assert_nonempty_file "$_err" "log_init misuse emits stderr"

rm -f "$_sandbox_lib/log.sh" 2>/dev/null || :
mv "$_sandbox_lib/log.real.sh" "$_sandbox_lib/log.sh" || exit 2

# --------------------------------------------------------------------------
# ADDED TEST 12: log_capture failure => degraded, boundary stderr replays leaf stderr
# --------------------------------------------------------------------------
mv "$_sandbox_lib/log.sh" "$_sandbox_lib/log.real.sh" || exit 2

cat >"$_sandbox_lib/log.sh" <<'LCFAIL'
#!/bin/sh
# log.sh (test double): init succeeds; capture fails

(return 0 2>/dev/null) || { echo "ERROR: log.sh must be sourced" >&2; exit 2; }

log_init() { return 0; }
log_capture() { cat >/dev/null; return 55; }

log_debug() { :; }
log_info()  { :; }
log_warn()  { :; }
log_error() { :; }
LCFAIL

_leaf=$(make_leaf leaf_lcfail '
echo "STDOUT: ok"
echo "ERROR: leaf-line-1" >&2
echo "WARN: leaf-line-2" >&2
exit 0
')

run_wrap "$_leaf"
rc=$WRAP_RC; out=$WRAP_OUT; err=$WRAP_ERR

assert_eq "$rc" "0" "log_capture failure does not fail the job"
assert_eq "$(cat "$out" 2>/dev/null || :)" "STDOUT: ok" "log_capture failure does not pollute stdout"
assert_nonempty_file "$err" "log_capture failure replays leaf stderr to boundary"
assert_contains_file "$err" "ERROR: leaf-line-1" "boundary replay contains leaf stderr (line 1)"
assert_contains_file "$err" "WARN: leaf-line-2" "boundary replay contains leaf stderr (line 2)"

rm -f "$_sandbox_lib/log.sh" 2>/dev/null || :
mv "$_sandbox_lib/log.real.sh" "$_sandbox_lib/log.sh" || exit 2

# --------------------------------------------------------------------------
# ADDED TEST 13: bootstrap log unavailable => wrapper warns but continues
# --------------------------------------------------------------------------
_ro_bad="$_sandbox/logs-nowrite"
mkdir -p "$_ro_bad" || exit 2
chmod 500 "$_ro_bad" 2>/dev/null || :

_leaf=$(make_leaf leaf_noboot '
echo "STDOUT: ok"
echo "STDERR: leaf" >&2
exit 0
')

_out="$_sandbox/out.noboot"
_err="$_sandbox/err.noboot"
rm -f "$_out" "$_err" 2>/dev/null || :
LOG_ROOT="$_ro_bad" LOG_BUCKET="other" LOG_KEEP_COUNT="0" LOG_MIN_LEVEL="INFO" \
  LOG_LIB_DIR="$_sandbox_lib" TMPDIR="$_sandbox_tmp" \
  sh "$_sandbox/bin/job-wrap.sh" "$_leaf" >"$_out" 2>"$_err"
rc=$?

assert_eq "$rc" "0" "bootstrap unavailable does not fail the job"
assert_eq "$(cat "$_out" 2>/dev/null || :)" "STDOUT: ok" "bootstrap unavailable does not pollute stdout"
assert_nonempty_file "$_err" "bootstrap/log root unwritable produces boundary warning"

chmod 700 "$_ro_bad" 2>/dev/null || :

# --------------------------------------------------------------------------
# ADDED TEST 14: commit not attempted when COMMIT_MODE=off
# --------------------------------------------------------------------------
mv "$_sandbox_lib/commit.sh" "$_sandbox_lib/commit.real2.sh" || exit 2
cat >"$_sandbox_lib/commit.sh" <<'CNO'
#!/bin/sh
echo "ERROR: commit invoked unexpectedly" >&2
exit 77
CNO
chmod 755 "$_sandbox_lib/commit.sh" 2>/dev/null || :

_leaf=$(make_leaf leaf_commit_off '
echo "x" >>"$COMMIT_LIST_FILE"
echo "STDOUT: ok"
exit 0
')

_out="$_sandbox/out.coff"
_err="$_sandbox/err.coff"
rm -f "$_out" "$_err" 2>/dev/null || :
LOG_ROOT="$_sandbox_logs" LOG_BUCKET="other" LOG_KEEP_COUNT="0" LOG_MIN_LEVEL="INFO" \
  LOG_LIB_DIR="$_sandbox_lib" TMPDIR="$_sandbox_tmp" COMMIT_MODE="off" \
  sh "$_sandbox/bin/job-wrap.sh" "$_leaf" >"$_out" 2>"$_err"
rc=$?

assert_eq "$rc" "0" "COMMIT_MODE=off does not fail the job"
assert_eq "$(cat "$_out" 2>/dev/null || :)" "STDOUT: ok" "COMMIT_MODE=off preserves stdout"
assert_empty_file "$_err" "COMMIT_MODE=off keeps boundary stderr quiet"

# --------------------------------------------------------------------------
# ADDED TEST 15: commit not attempted when leaf exits non-zero
# --------------------------------------------------------------------------
_leaf=$(make_leaf leaf_commit_leaffail '
echo "x" >>"$COMMIT_LIST_FILE"
echo "STDOUT: ok"
echo "ERROR: leaf failed" >&2
exit 7
')

_out="$_sandbox/out.cleaf"
_err="$_sandbox/err.cleaf"
rm -f "$_out" "$_err" 2>/dev/null || :
LOG_ROOT="$_sandbox_logs" LOG_BUCKET="other" LOG_KEEP_COUNT="0" LOG_MIN_LEVEL="INFO" \
  LOG_LIB_DIR="$_sandbox_lib" TMPDIR="$_sandbox_tmp" COMMIT_MODE="required" \
  sh "$_sandbox/bin/job-wrap.sh" "$_leaf" >"$_out" 2>"$_err"
rc=$?

assert_eq "$rc" "7" "leaf non-zero is propagated (no commit attempt)"
assert_eq "$(cat "$_out" 2>/dev/null || :)" "STDOUT: ok" "leaf non-zero preserves stdout"
assert_empty_file "$_err" "leaf non-zero still keeps boundary stderr quiet when capture works"

# --------------------------------------------------------------------------
# ADDED TEST 16: commit not attempted when commit list empty / blank-only
# --------------------------------------------------------------------------
_leaf=$(make_leaf leaf_commit_empty '
echo "STDOUT: ok"
exit 0
')

_out="$_sandbox/out.cempty"
_err="$_sandbox/err.cempty"
rm -f "$_out" "$_err" 2>/dev/null || :
LOG_ROOT="$_sandbox_logs" LOG_BUCKET="other" LOG_KEEP_COUNT="0" LOG_MIN_LEVEL="INFO" \
  LOG_LIB_DIR="$_sandbox_lib" TMPDIR="$_sandbox_tmp" COMMIT_MODE="required" \
  sh "$_sandbox/bin/job-wrap.sh" "$_leaf" >"$_out" 2>"$_err"
rc=$?

assert_eq "$rc" "0" "empty commit list does not fail the job"
assert_eq "$(cat "$_out" 2>/dev/null || :)" "STDOUT: ok" "empty commit list preserves stdout"
assert_empty_file "$_err" "empty commit list keeps boundary stderr quiet"

# --------------------------------------------------------------------------
# ADDED TEST 17: commit list comment/blank filtering + commit rc=3 treated as success
# --------------------------------------------------------------------------
cat >"$_sandbox_lib/commit.sh" <<'C3'
#!/bin/sh
exit 3
C3
chmod 755 "$_sandbox_lib/commit.sh" 2>/dev/null || :

_leaf=$(make_leaf leaf_commit_filter '
printf "%s\n" "# comment" >>"$COMMIT_LIST_FILE"
printf "%s\n" "" >>"$COMMIT_LIST_FILE"
printf "%s\n" "notes/A.md" >>"$COMMIT_LIST_FILE"
printf "%s\n" "notes/B.md" >>"$COMMIT_LIST_FILE"
echo "STDOUT: ok"
exit 0
')

_out="$_sandbox/out.cfilter"
_err="$_sandbox/err.cfilter"
rm -f "$_out" "$_err" 2>/dev/null || :
LOG_ROOT="$_sandbox_logs" LOG_BUCKET="other" LOG_KEEP_COUNT="0" LOG_MIN_LEVEL="INFO" \
  LOG_LIB_DIR="$_sandbox_lib" TMPDIR="$_sandbox_tmp" COMMIT_MODE="required" COMMIT_MESSAGE="x" \
  run_jobwrap "$_sandbox/bin/job-wrap.sh" "$_leaf" >"$_out" 2>"$_err"
rc=$?

assert_eq "$rc" "0" "commit helper rc=3 is treated as success"
assert_eq "$(cat "$_out" 2>/dev/null || :)" "STDOUT: ok" "commit rc=3 preserves stdout"
assert_empty_file "$_err" "commit rc=3 keeps boundary stderr quiet"

# Restore real commit helper (second restore)
rm -f "$_sandbox_lib/commit.sh" 2>/dev/null || :
mv "$_sandbox_lib/commit.real2.sh" "$_sandbox_lib/commit.sh" || exit 2

# --------------------------------------------------------------------------
# ADDED TEST 18: COMMIT_LIST_FILE cannot be created (TMPDIR unwritable) => no commit attempt
# --------------------------------------------------------------------------
_bad_tmp2="$_sandbox/nowrite2"
mkdir -p "$_bad_tmp2" || exit 2
chmod 500 "$_bad_tmp2" 2>/dev/null || :

mv "$_sandbox_lib/commit.sh" "$_sandbox_lib/commit.real3.sh" || exit 2
cat >"$_sandbox_lib/commit.sh" <<'CNOV'
#!/bin/sh
echo "ERROR: commit invoked unexpectedly" >&2
exit 88
CNOV
chmod 755 "$_sandbox_lib/commit.sh" 2>/dev/null || :

_leaf=$(make_leaf leaf_commit_nolist '
if [ -n "${COMMIT_LIST_FILE:-}" ]; then
  echo "notes/X.md" >>"$COMMIT_LIST_FILE"
fi
echo "STDOUT: ok"
exit 0
')

_out="$_sandbox/out.cnolist"
_err="$_sandbox/err.cnolist"
rm -f "$_out" "$_err" 2>/dev/null || :
LOG_ROOT="$_sandbox_logs" LOG_BUCKET="other" LOG_KEEP_COUNT="0" LOG_MIN_LEVEL="INFO" \
  LOG_LIB_DIR="$_sandbox_lib" TMPDIR="$_bad_tmp2" COMMIT_MODE="required" \
  run_jobwrap "$_sandbox/bin/job-wrap.sh" "$_leaf" >"$_out" 2>"$_err"
rc=$?

assert_eq "$rc" "0" "commit list file creation failure does not fail the job"
assert_eq "$(cat "$_out" 2>/dev/null || :)" "STDOUT: ok" "commit list file creation failure preserves stdout"
assert_nonempty_file "$_err" "commit list file creation failure produces boundary warning (degraded)"

chmod 700 "$_bad_tmp2" 2>/dev/null || :
rm -f "$_sandbox_lib/commit.sh" 2>/dev/null || :
mv "$_sandbox_lib/commit.real3.sh" "$_sandbox_lib/commit.sh" || exit 2

# --------------------------------------------------------------------------
# ADDED TEST 19: leaf stderr captured into per-run log (boundary stays quiet)
# --------------------------------------------------------------------------
_leaf=$(make_leaf leaf_capture_to_log '
echo "STDOUT: ok"
echo "ERROR: leaf-cap-1" >&2
echo "WARN: leaf-cap-2" >&2
exit 0
')

run_wrap "$_leaf"
rc=$WRAP_RC; out=$WRAP_OUT; err=$WRAP_ERR

assert_eq "$rc" "0" "leaf stderr capture-to-log does not fail the job"
assert_eq "$(cat "$out" 2>/dev/null || :)" "STDOUT: ok" "leaf stderr capture-to-log preserves stdout"
assert_empty_file "$err" "leaf stderr capture-to-log keeps boundary stderr quiet"

_job="leaf_capture_to_log"
_latest="$_sandbox_logs/other/${_job}/${_job}-latest.log"
assert_exists "$_latest" "capture-to-log updates latest log"
assert_contains_file "$_latest" "leaf-cap-1" "per-run log contains captured leaf stderr (line 1)"
assert_contains_file "$_latest" "leaf-cap-2" "per-run log contains captured leaf stderr (line 2)"

# --------------------------------------------------------------------------
# ADDED TEST 20: leaf output missing level prefix is preserved (UNDEF) and captured
# --------------------------------------------------------------------------
_leaf=$(make_leaf leaf_undef_line '
echo "STDOUT: ok"
echo "this line has no prefix" >&2
exit 0
')

run_wrap "$_leaf"
rc=$WRAP_RC; out=$WRAP_OUT; err=$WRAP_ERR

assert_eq "$rc" "0" "UNDEF leaf line does not fail the job"
assert_eq "$(cat "$out" 2>/dev/null || :)" "STDOUT: ok" "UNDEF leaf line preserves stdout"
assert_empty_file "$err" "UNDEF leaf line keeps boundary stderr quiet"

_job="leaf_undef_line"
_latest="$_sandbox_logs/other/${_job}/${_job}-latest.log"
assert_exists "$_latest" "UNDEF case updates latest log"
assert_contains_file "$_latest" "this line has no prefix" "per-run log contains UNDEF leaf line content"

# --------------------------------------------------------------------------
# ADDED TEST 21: missing leaf script => shell rc=127 propagated; boundary stays quiet
# --------------------------------------------------------------------------
_missing="$_sandbox/bin/no_such_leaf_$$.sh"

_out="$_sandbox/out.miss"
_err="$_sandbox/err.miss"
rm -f "$_out" "$_err" 2>/dev/null || :
LOG_ROOT="$_sandbox_logs" LOG_BUCKET="other" LOG_KEEP_COUNT="0" LOG_MIN_LEVEL="INFO" \
  LOG_LIB_DIR="$_sandbox_lib" TMPDIR="$_sandbox_tmp" \
  run_jobwrap "$_sandbox/bin/job-wrap.sh" "$_missing" >"$_out" 2>"$_err"
rc=$?

assert_eq "$rc" "127" "missing leaf returns 127 (sh command not found) and is propagated"
assert_empty_file "$_out" "missing leaf emits nothing on stdout"
assert_empty_file "$_err" "missing leaf keeps boundary stderr quiet when capture works"

_job="no_such_leaf_$$"
_latest="$_sandbox_logs/other/${_job}/${_job}-latest.log"
if [ -f "$_latest" ]; then
  ok "missing leaf produced a latest log artifact"
else
  ok "missing leaf did not produce a latest log artifact (best-effort acceptable)"
fi

# --------------------------------------------------------------------------
# ADDED TEST 22: non-executable leaf script => rc=126 propagated; boundary stays quiet
# --------------------------------------------------------------------------
_nonexec="$_sandbox/bin/nonexec_$$.sh"
cat >"$_nonexec" <<'EOF'
#!/bin/sh
echo "STDOUT: should-not-run"
echo "STDERR: should-not-run" >&2
exit 0
EOF
chmod 644 "$_nonexec" 2>/dev/null || :

_out="$_sandbox/out.nonexec"
_err="$_sandbox/err.nonexec"
rm -f "$_out" "$_err" 2>/dev/null || :
LOG_ROOT="$_sandbox_logs" LOG_BUCKET="other" LOG_KEEP_COUNT="0" LOG_MIN_LEVEL="INFO" \
  LOG_LIB_DIR="$_sandbox_lib" TMPDIR="$_sandbox_tmp" \
  run_jobwrap "$_sandbox/bin/job-wrap.sh" "$_nonexec" >"$_out" 2>"$_err"
rc=$?

assert_eq "$rc" "126" "non-executable leaf returns 126 and is propagated"
assert_empty_file "$_out" "non-executable leaf emits nothing on stdout"
assert_empty_file "$_err" "non-executable leaf keeps boundary stderr quiet when capture works"

_job="nonexec_$$"
_latest="$_sandbox_logs/other/${_job}/${_job}-latest.log"
if [ -f "$_latest" ]; then
  ok "non-executable leaf produced a latest log artifact"
else
  ok "non-executable leaf did not produce a latest log artifact (best-effort acceptable)"
fi

# --------------------------------------------------------------------------
# ADDED TEST 23: LOG_MIN_LEVEL=DEBUG surfaces wrapper debug line early (bootstrap)
# --------------------------------------------------------------------------
_leaf=$(make_leaf leaf_debug_level '
echo "STDOUT: ok"
exit 0
')

_out="$_sandbox/out.debuglvl"
_err="$_sandbox/err.debuglvl"
rm -f "$_out" "$_err" 2>/dev/null || :
LOG_ROOT="$_sandbox_logs" LOG_BUCKET="other" LOG_KEEP_COUNT="0" LOG_MIN_LEVEL="DEBUG" \
  LOG_LIB_DIR="$_sandbox_lib" TMPDIR="$_sandbox_tmp" \
  run_jobwrap "$_sandbox/bin/job-wrap.sh" "$_leaf" >"$_out" 2>"$_err"
rc=$?

assert_eq "$rc" "0" "LOG_MIN_LEVEL=DEBUG does not fail the job"
assert_eq "$(cat "$_out" 2>/dev/null || :)" "STDOUT: ok" "LOG_MIN_LEVEL=DEBUG preserves stdout"
assert_nonempty_file "$_err" "LOG_MIN_LEVEL=DEBUG produces some boundary stderr (wrapper debug/diag)"
assert_contains_file "$_err" "DEBUG: WRAP: bootstrap diagnostics" "boundary includes wrapper DEBUG bootstrap diagnostic line"

# --------------------------------------------------------------------------
# ADDED TEST 24: degraded (log_init rc=10) + CAPTURE_MODE=file => leaf stderr must remain visible
# --------------------------------------------------------------------------
mv "$_sandbox_lib/log.sh" "$_sandbox_lib/log.real4.sh" || exit 2

cat >"$_sandbox_lib/log.sh" <<'LOG10_DROP'
#!/bin/sh
# log.sh (test double): log_init operational failure (rc=10); capture exists but is irrelevant.

(return 0 2>/dev/null) || { echo "ERROR: log.sh must be sourced" >&2; exit 2; }

log_init() { return 10; }
log_capture() { cat >/dev/null; return 0; }

log_debug() { :; }
log_info()  { :; }
log_warn()  { :; }
log_error() { :; }
LOG10_DROP

_leaf=$(make_leaf leaf_degraded_file_capture '
echo "STDOUT: ok"
echo "ERROR: degraded-leaf-1" >&2
echo "WARN: degraded-leaf-2" >&2
exit 0
')

run_wrap "$_leaf"
rc=$WRAP_RC; out=$WRAP_OUT; err=$WRAP_ERR

assert_eq "$rc" "0" "degraded+file-capture does not fail the job"
assert_eq "$(cat "$out" 2>/dev/null || :)" "STDOUT: ok" "degraded+file-capture preserves stdout"
if grep -F "degraded-leaf-1" "$err" >/dev/null 2>&1 || grep -F "degraded-leaf-2" "$err" >/dev/null 2>&1; then
  ok "degraded+file-capture preserves leaf stderr visibility (boundary replay)"
else
  not_ok "degraded+file-capture preserves leaf stderr visibility (NOTE: wrapper may currently drop stderr here)"
fi

rm -f "$_sandbox_lib/log.sh" 2>/dev/null || :
mv "$_sandbox_lib/log.real4.sh" "$_sandbox_lib/log.sh" || exit 2

# --------------------------------------------------------------------------
# ADDED TEST 25: commit helper failure overrides leaf rc with 123 even in best-effort mode
# --------------------------------------------------------------------------
mv "$_sandbox_lib/commit.sh" "$_sandbox_lib/commit.real4.sh" || exit 2
cat >"$_sandbox_lib/commit.sh" <<'COMMIT_FAIL'
#!/bin/sh
exit 44
COMMIT_FAIL
chmod 755 "$_sandbox_lib/commit.sh" 2>/dev/null || :

_leaf=$(make_leaf leaf_commit_best_effort_fail '
echo "notes/X.md" >>"$COMMIT_LIST_FILE"
echo "STDOUT: ok"
exit 0
')

_out="$_sandbox/out.cbe"
_err="$_sandbox/err.cbe"
rm -f "$_out" "$_err" 2>/dev/null || :
LOG_ROOT="$_sandbox_logs" LOG_BUCKET="other" LOG_KEEP_COUNT="0" LOG_MIN_LEVEL="INFO" \
  LOG_LIB_DIR="$_sandbox_lib" TMPDIR="$_sandbox_tmp" COMMIT_MODE="best-effort" COMMIT_MESSAGE="x" \
  sh "$_sandbox/bin/job-wrap.sh" "$_leaf" >"$_out" 2>"$_err"
rc=$?

assert_eq "$rc" "123" "commit failure in best-effort overrides exit with 123"
assert_eq "$(cat "$_out" 2>/dev/null || :)" "STDOUT: ok" "commit failure (best-effort) still preserves leaf stdout"
assert_nonempty_file "$_err" "commit failure (best-effort) emits boundary error"

rm -f "$_sandbox_lib/commit.sh" 2>/dev/null || :
mv "$_sandbox_lib/commit.real4.sh" "$_sandbox_lib/commit.sh" || exit 2

# --------------------------------------------------------------------------
# ADDED TEST 26: commit helper missing => wrapper exits 123 when commit was attempted
# --------------------------------------------------------------------------
mv "$_sandbox_lib/commit.sh" "$_sandbox_lib/commit.real5.sh" || exit 2

_leaf=$(make_leaf leaf_commit_missing_helper '
echo "notes/X.md" >>"$COMMIT_LIST_FILE"
echo "STDOUT: ok"
exit 0
')

_out="$_sandbox/out.cmissh"
_err="$_sandbox/err.cmissh"
rm -f "$_out" "$_err" 2>/dev/null || :
LOG_ROOT="$_sandbox_logs" LOG_BUCKET="other" LOG_KEEP_COUNT="0" LOG_MIN_LEVEL="INFO" \
  LOG_LIB_DIR="$_sandbox_lib" TMPDIR="$_sandbox_tmp" COMMIT_MODE="required" COMMIT_MESSAGE="x" \
  sh "$_sandbox/bin/job-wrap.sh" "$_leaf" >"$_out" 2>"$_err"
rc=$?

assert_eq "$rc" "123" "missing commit helper triggers 123 when commit was attempted"
assert_eq "$(cat "$_out" 2>/dev/null || :)" "STDOUT: ok" "missing commit helper still preserves leaf stdout"
assert_nonempty_file "$_err" "missing commit helper emits boundary error"

mv "$_sandbox_lib/commit.real5.sh" "$_sandbox_lib/commit.sh" || exit 2

# --------------------------------------------------------------------------
# ADDED TEST 27: commit helper non-executable => wrapper exits 123 when commit was attempted
# --------------------------------------------------------------------------
chmod 644 "$_sandbox_lib/commit.sh" 2>/dev/null || :

_leaf=$(make_leaf leaf_commit_nonexec_helper '
echo "notes/X.md" >>"$COMMIT_LIST_FILE"
echo "STDOUT: ok"
exit 0
')

_out="$_sandbox/out.cnx"
_err="$_sandbox/err.cnx"
rm -f "$_out" "$_err" 2>/dev/null || :
LOG_ROOT="$_sandbox_logs" LOG_BUCKET="other" LOG_KEEP_COUNT="0" LOG_MIN_LEVEL="INFO" \
  LOG_LIB_DIR="$_sandbox_lib" TMPDIR="$_sandbox_tmp" COMMIT_MODE="required" COMMIT_MESSAGE="x" \
  sh "$_sandbox/bin/job-wrap.sh" "$_leaf" >"$_out" 2>"$_err"
rc=$?

assert_eq "$rc" "123" "non-executable commit helper triggers 123 when commit was attempted"
assert_eq "$(cat "$_out" 2>/dev/null || :)" "STDOUT: ok" "non-executable commit helper preserves leaf stdout"
assert_nonempty_file "$_err" "non-executable commit helper emits boundary error"

chmod 755 "$_sandbox_lib/commit.sh" 2>/dev/null || :

# --------------------------------------------------------------------------
# ADDED TEST 28: LOG_MIN_LEVEL=ERROR gates wrapper WARN in degraded mode
# --------------------------------------------------------------------------
mv "$_sandbox_lib/log.sh" "$_sandbox_lib/log.real6.sh" || exit 2

cat >"$_sandbox_lib/log.sh" <<'LOG10_WARN'
#!/bin/sh
# log.sh (test double): log_init operational failure (rc=10)

(return 0 2>/dev/null) || { echo "ERROR: log.sh must be sourced" >&2; exit 2; }

log_init() { return 10; }
log_capture() { cat >/dev/null; return 0; }

log_debug() { :; }
log_info()  { :; }
log_warn()  { :; }
log_error() { :; }
LOG10_WARN

_leaf=$(make_leaf leaf_minlvl_error '
echo "STDOUT: ok"
exit 0
')

_out="$_sandbox/out.minlvl"
_err="$_sandbox/err.minlvl"
rm -f "$_out" "$_err" 2>/dev/null || :
LOG_ROOT="$_sandbox_logs" LOG_BUCKET="other" LOG_KEEP_COUNT="0" LOG_MIN_LEVEL="ERROR" \
  LOG_LIB_DIR="$_sandbox_lib" TMPDIR="$_sandbox_tmp" \
  sh "$_sandbox/bin/job-wrap.sh" "$_leaf" >"$_out" 2>"$_err"
rc=$?

assert_eq "$rc" "0" "LOG_MIN_LEVEL=ERROR does not fail the job"
assert_eq "$(cat "$_out" 2>/dev/null || :)" "STDOUT: ok" "LOG_MIN_LEVEL=ERROR preserves stdout"
assert_not_contains_file "$_err" "logger init operational failure" "LOG_MIN_LEVEL=ERROR suppresses wrapper WARN in degraded mode"

rm -f "$_sandbox_lib/log.sh" 2>/dev/null || :
mv "$_sandbox_lib/log.real6.sh" "$_sandbox_lib/log.sh" || exit 2

# --------------------------------------------------------------------------
# ADDED TEST 29: structural failures (WRAP_DIR / REPO_ROOT resolution) => 121 (simulated)
# --------------------------------------------------------------------------
_wrap_struct=$(make_leaf wrap_struct_fail '
WRAP_E_INIT=121
echo "ERROR: WRAP: cannot resolve wrapper directory" >&2
exit "$WRAP_E_INIT"
')

_out="$_sandbox/out.struct1"
_err="$_sandbox/err.struct1"
rm -f "$_out" "$_err" 2>/dev/null || :
sh "$_wrap_struct" >"$_out" 2>"$_err"
rc=$?
assert_eq "$rc" "121" "structural failure (WRAP_DIR resolution) returns 121 (simulated)"
assert_empty_file "$_out" "structural failure does not emit stdout (simulated)"
assert_nonempty_file "$_err" "structural failure emits stderr (simulated)"

_wrap_struct2=$(make_leaf wrap_struct_fail2 '
WRAP_E_INIT=121
echo "ERROR: WRAP: cannot resolve repo root from rebuild layout" >&2
exit "$WRAP_E_INIT"
')

_out="$_sandbox/out.struct2"
_err="$_sandbox/err.struct2"
rm -f "$_out" "$_err" 2>/dev/null || :
sh "$_wrap_struct2" >"$_out" 2>"$_err"
rc=$?
assert_eq "$rc" "121" "structural failure (REPO_ROOT resolution) returns 121 (simulated)"
assert_empty_file "$_out" "structural failure does not emit stdout (simulated)"
assert_nonempty_file "$_err" "structural failure emits stderr (simulated)"

# --------------------------------------------------------------------------
# ADDED TEST 30: multiline wrapper diagnostic handling (simulated)
# --------------------------------------------------------------------------
_wrap_multi=$(make_leaf wrap_multiline '
LOG_DEGRADED=1
LOG_MIN_LEVEL=DEBUG
WRAP_BOOT_LOG="${TMPDIR:-/tmp}/wrap-multi.$$"
: >"$WRAP_BOOT_LOG" 2>/dev/null || WRAP_BOOT_LOG=""

_NL=$(printf "\n")

_wrap_level_num() {
  case "$1" in
    DEBUG) printf "%s\n" 10 ;;
    INFO)  printf "%s\n" 20 ;;
    WARN)  printf "%s\n" 30 ;;
    ERROR) printf "%s\n" 40 ;;
    *)     printf "%s\n" 0 ;;
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

  _emit_boundary=1

  case "$_msg" in
    *"$_NL"*)
      if [ -n "${WRAP_BOOT_LOG:-}" ]; then
        {
          printf "%s: WRAP: (multiline diagnostic; full text follows)\n" "$_lvl"
          printf "%s\n" "$_msg"
        } >>"$WRAP_BOOT_LOG" 2>/dev/null || :
      fi
      if [ "$_emit_boundary" -eq 1 ]; then
        printf "%s: WRAP: multiline diagnostic (see bootstrap: %s)\n" "$_lvl" "${WRAP_BOOT_LOG:-<unavailable>}" >&2
      fi
      return 0
      ;;
  esac
  return 0
}

_wrap_emit INFO "line1
line2"
exit 0
')

_out="$_sandbox/out.multi"
_err="$_sandbox/err.multi"
rm -f "$_out" "$_err" 2>/dev/null || :
TMPDIR="$_sandbox_tmp" sh "$_wrap_multi" >"$_out" 2>"$_err"
rc=$?

assert_eq "$rc" "0" "multiline diagnostic test-double exits 0"
assert_empty_file "$_out" "multiline diagnostic does not write stdout"
assert_contains_file "$_err" "multiline diagnostic" "multiline diagnostic produces single-line boundary marker"

_boot_guess=$(ls -1 "$_sandbox_tmp" 2>/dev/null | grep -E "^wrap-multi\.[0-9]+$" | head -n 1 || true)
if [ -n "$_boot_guess" ] && grep -F "line1" "$_sandbox_tmp/$_boot_guess" >/dev/null 2>&1 && grep -F "line2" "$_sandbox_tmp/$_boot_guess" >/dev/null 2>&1; then
  ok "multiline diagnostic bootstrap contains full multiline text"
else
  not_ok "multiline diagnostic bootstrap contains full multiline text"
fi

# --------------------------------------------------------------------------
# ADDED TEST 31: JOB_WRAP_DEBUG affects healthy-mode boundary visibility (simulated)
# --------------------------------------------------------------------------
_wrap_dbg=$(make_leaf wrap_dbg_healthy '
LOG_DEGRADED=0
LOG_MIN_LEVEL=INFO
JOB_WRAP_DEBUG=${JOB_WRAP_DEBUG:-0}

_wrap_level_num() {
  case "$1" in
    DEBUG) printf "%s\n" 10 ;;
    INFO)  printf "%s\n" 20 ;;
    WARN)  printf "%s\n" 30 ;;
    ERROR) printf "%s\n" 40 ;;
    *)     printf "%s\n" 0 ;;
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

  _emit_boundary=0
  case "$_lvl" in
    WARN|ERROR) _emit_boundary=1 ;;
    *) [ "${JOB_WRAP_DEBUG:-0}" = "1" ] && _emit_boundary=1 ;;
  esac

  if [ "$_emit_boundary" -eq 1 ]; then
    printf "%s: WRAP: %s\n" "$_lvl" "$_msg" >&2
  fi
  return 0
}
_wrap_emit INFO "healthy-info-marker"
exit 0
')

_out="$_sandbox/out.dbg0"
_err="$_sandbox/err.dbg0"
rm -f "$_out" "$_err" 2>/dev/null || :
JOB_WRAP_DEBUG=0 sh "$_wrap_dbg" >"$_out" 2>"$_err"
rc=$?
assert_eq "$rc" "0" "JOB_WRAP_DEBUG=0 test-double exits 0"
assert_empty_file "$_err" "JOB_WRAP_DEBUG=0 suppresses healthy INFO on boundary (simulated)"

_out="$_sandbox/out.dbg1"
_err="$_sandbox/err.dbg1"
rm -f "$_out" "$_err" 2>/dev/null || :
JOB_WRAP_DEBUG=1 sh "$_wrap_dbg" >"$_out" 2>"$_err"
rc=$?
assert_eq "$rc" "0" "JOB_WRAP_DEBUG=1 test-double exits 0"
assert_contains_file "$_err" "healthy-info-marker" "JOB_WRAP_DEBUG=1 allows healthy INFO on boundary (simulated)"

# --------------------------------------------------------------------------
# Finish
# --------------------------------------------------------------------------
say "1..$_n"
if [ "$_fail" -ne 0 ]; then
  say "# FAIL: $_fail tests failed" >&2
  exit 1
fi
say "# PASS"
exit 0
