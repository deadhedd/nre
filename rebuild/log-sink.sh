#!/bin/sh
# rebuild/log-sink.sh
#
# Logging sink lifecycle manager.
# Library-only. MUST be sourced by job-wrap.sh (via log.sh).
# Owns log sink lifecycle: opens the per-run log file, maintains latest pointer,
# retention, and FD management.
#
# Contract authority: CONTRACT(21).md sed 2.2, sec 3.2, Appendix C.6
#
# IMPORTANT (v0.9+): Wrapper-context validation (JOB_WRAP_ACTIVE=1) is owned
# by log.sh (facade). This component enforces *facade ownership* before any
# sink mutation and returns 11 on missing facade context.
#
# NOTE: Sink-required env vars (JOB_NAME, LOG_FILE) are treated as logger helper
# misuse (return 11). This indicates missing facade-provided context; log.sh /
# job-wrap decide whether this degrades to stderr-only logging or escalates to a
# hard wrapper failure.
#
# NOTE (v0.9+): Log filenames are contract-controlled and MUST NOT contain
# whitespace or newlines. Per-run log filenames MUST be lexicographically
# sortable by timestamp (canonical form: <job>-YYYY-MM-DD-HHMMSS.log), so
# retention pruning can be deterministic by filename order.
#
# NOTE (v0.9+): Retention pruning is directory-local: only direct children of
# the log directory containing LOG_FILE are considered. No recursion.

# ---- guard: library-only ---------------------------------------------------

# Robust "sourced vs executed" detection (catches: ./log-sink.sh AND sh log-sink.sh)
# In POSIX sh, `return` is valid only when sourced; if executed, it errors.
if (return 0 2>/dev/null); then
    : # sourced, OK
else
    echo "ERROR: log-sink.sh is a library and must be sourced, not executed" >&2
    exit 2
fi

case "${LOG_SINK_LOADED:-0}" in
    1) return 0 ;;
esac
LOG_SINK_LOADED=1

# ---- internal scratch ------------------------------------------------------

_ls_log_dir=
_ls_latest_link=
_ls_keep_count=
_ls_job=

# Additional scratch used by retention logic
_ls_pattern=
_ls_sorted_list=
_ls_total=
_ls_delete_count=
_ls_delete_list=
_ls_path=
_ls_rc=
_ls_rm_rc=
_ls_msg=
_ls_j=
_ls_base=
_ls_rel=

# ---- helpers ---------------------------------------------------------------

_ls_err() {
    # diagnostics-only; never stdout
    # Strong single-line guarantee:
    #   - strip control chars (incl. \r, \n) to ensure exactly one line
    _ls_msg=$*
    _ls_msg=$(printf '%s' "$_ls_msg" | LC_ALL=C tr -d '[:cntrl:]')
    printf 'LOG_SINK: %s\n' "$_ls_msg" >&2
}

_ls_fail() {
    # operational failure for logger helper contract
    # return code 10 is the canonical "helper operational failure"
    _ls_err "ERROR: $*"
    return 10
}

_ls_fail_misuse() {
    # misuse failure for logger helper contract
    # return code 11 is the canonical "helper misuse (missing facade context)"
    _ls_err "ERROR: $*"
    return 11
}

_ls_require_facade() {
    # Missing facade context is a logger helper misuse.
    # When sourced: MUST NOT exit; return 11.
    if [ "${LOG_FACADE_ACTIVE:-}" != "1" ]; then
        _ls_fail_misuse "invoked without facade context (LOG_FACADE_ACTIVE!=1)"
        return 11
    fi
    return 0
}

_ls_validate_job_name() {
    # Contract: JOB_NAME must be safe for filenames and globs.
    # Enforced here (stricter-than-contract is allowed):
    # - non-empty
    # - [A-Za-z0-9._-] only
    # - no path separators
    # - no glob metacharacters
    _ls_j=$1

    if [ -z "$_ls_j" ]; then
        _ls_fail_misuse "missing required env var: JOB_NAME"
        return 11
    fi

    # Only allow [A-Za-z0-9._-]
    if ! printf '%s' "$_ls_j" | LC_ALL=C grep -Eq '^[A-Za-z0-9._-]+$'; then
        _ls_fail_misuse "invalid JOB_NAME (allowed: [A-Za-z0-9._-]): $_ls_j"
        return 11
    fi

    if [ "$_ls_j" = "." ] || [ "$_ls_j" = ".." ]; then
        _ls_fail_misuse "invalid JOB_NAME ('.' and '..' are forbidden): $_ls_j"
        return 11
    fi

    return 0
}

_ls_validate_log_file() {
    # Validate LOG_FILE enough to preserve downstream assumptions:
    # - non-empty
    # - basename matches canonical per-run shape:
    #     <JOB_NAME>-YYYY-MM-DD-HHMMSS.log
    # - basename is ASCII-safe for globbing and sorting
    _ls_path=$1

    if [ -z "$_ls_path" ]; then
        _ls_fail_misuse "missing required env var: LOG_FILE"
        return 11
    fi

    _ls_base=$(basename "$_ls_path")

    # Basename must be ASCII-safe: [A-Za-z0-9._-] only
    if ! printf '%s' "$_ls_base" | LC_ALL=C grep -Eq '^[A-Za-z0-9._-]+$'; then
        _ls_fail_misuse "invalid LOG_FILE basename (allowed: [A-Za-z0-9._-]): $_ls_base"
        return 11
    fi

    # Must match: ${JOB_NAME}-YYYY-MM-DD-HHMMSS.log
    if ! printf '%s' "$_ls_base" | LC_ALL=C grep -Eq "^${JOB_NAME}-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]\\.log$"; then
        _ls_fail_misuse "invalid LOG_FILE basename (expected ${JOB_NAME}-YYYY-MM-DD-HHMMSS.log): $_ls_base"
        return 11
    fi

    return 0
}

_ls_require_env_hard() {
    _ls_validate_job_name "${JOB_NAME:-}" || return $?
    _ls_validate_log_file "${LOG_FILE:-}" || return $?
    return 0
}

_ls_mkdir_p() {
    if [ -d "$1" ]; then
        return 0
    fi
    mkdir -p "$1" || _ls_fail "cannot create directory: $1"
}

# ---- retention -------------------------------------------------------------
# NOTE: Defined before log_sink_init so shells that don't pre-parse function
# bodies (e.g., some ksh configurations) still have it available.

_ls_prune_logs() {
    _ls_keep_count=${LOG_KEEP_COUNT:-0}

    # Must be a non-negative integer. Otherwise treat as 0.
    if ! printf '%s' "$_ls_keep_count" | LC_ALL=C grep -Eq '^[0-9]+$'; then
        _ls_keep_count=0
    fi
    [ "$_ls_keep_count" -gt 0 ] || return 0

    _ls_pattern="${_ls_job}-????-??-??-??????.log"

    _ls_sorted_list=$(
        find "$_ls_log_dir" -type f -name "$_ls_pattern" 2>/dev/null \
        | while IFS= read -r _ls_path; do
              # Directory-local retention:
              # keep only direct children of $_ls_log_dir (no recursion)
              _ls_rel=${_ls_path#$_ls_log_dir/}

              # If it contains a slash, it's in a subdir -> exclude.
              if [ "${_ls_rel#*/}" != "$_ls_rel" ]; then
                  :
              else
                  printf '%s\n' "$_ls_path"
              fi
          done \
        | sort
    ) || {
        _ls_fail "prune list generation failed"
        return 10
    }

    [ -n "${_ls_sorted_list:-}" ] || return 0

    _ls_total=$(printf '%s\n' "$_ls_sorted_list" | awk 'END { print NR }') || {
        _ls_fail "prune count failed"
        return 10
    }

    [ "$_ls_total" -le "$_ls_keep_count" ] && return 0

    _ls_delete_count=$(( _ls_total - _ls_keep_count ))

    _ls_delete_list=$(
        printf '%s\n' "$_ls_sorted_list" \
        | awk -v del="$_ls_delete_count" 'NR <= del { print }'
    ) || {
        _ls_fail "prune selection failed"
        return 10
    }

    [ -n "${_ls_delete_list:-}" ] || return 0

    # Delete line-by-line (no word-splitting)
    _ls_rc=0
    while IFS= read -r _ls_path; do
        [ -n "$_ls_path" ] || continue
        rm -f "$_ls_path"
        _ls_rm_rc=$?
        if [ "$_ls_rm_rc" -ne 0 ]; then
            _ls_fail "cannot delete old log: $_ls_path (rm exit=$_ls_rm_rc)"
            _ls_rc=10
            break
        fi
    done <<EOF
$_ls_delete_list
EOF

    return $_ls_rc
}

# ---- public API ------------------------------------------------------------

log_sink_init() {
    _ls_require_facade || return $?
    _ls_require_env_hard || return $?

    _ls_job=$JOB_NAME
    _ls_log_dir=$(dirname "$LOG_FILE")
    _ls_latest_link="${_ls_log_dir}/${_ls_job}-latest.log"

    _ls_mkdir_p "$_ls_log_dir" || return $?

    # Ensure fd 3 is free before opening (POSIX-safe)
    exec 3>&- 2>/dev/null || :

    exec 3>>"$LOG_FILE" || {
        _ls_fail "cannot open log file: $LOG_FILE"
        return 10
    }

    ln -sf "$LOG_FILE" "$_ls_latest_link" || {
        _ls_fail "cannot update latest log symlink: $_ls_latest_link"
        return 10
    }

    _ls_prune_logs || return $?
    return 0
}

log_sink_close() {
    _ls_require_facade || return $?
    exec 3>&- 2>/dev/null || :
    return 0
}

# ---- internal API (logger subsystem only) ----------------------------------

_ls_write_line() {
    _ls_require_facade || return $?
    printf '%s\n' "$1" >&3 2>/dev/null || {
        _ls_fail "failed to write log line to fd 3 (sink not open?)"
        return 10
    }
    return 0
}
