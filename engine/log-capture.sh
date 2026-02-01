#!/bin/sh
# rebuild/log-capture.sh
#
# Library-only logging helper.
# Captures stdin line-by-line and forwards each line through log-format,
# then writes formatted lines to the active log sink.
#
# CONTRACT:
# - MUST be sourced, not executed
# - MUST NOT emit observable stdout at the job boundary
#   (internal helper stdout is permitted only when fully captured)
# - MUST NOT call exit when sourced (except executed-directly guard)
# - MUST return status codes only
# - Wrapper/log.sh own escalation policy
#
# NOTE:
# - This helper does NOT sanitize or timestamp lines itself.
#   Those responsibilities belong to log-format.sh (via log_format_build_line).

###############################################################################
# guard: library-only
###############################################################################

# Robust “sourced vs executed” detection (catches: ./log-capture.sh AND sh log-capture.sh)
# In POSIX sh, `return` is valid only when sourced; if executed, it errors.
if (return 0 2>/dev/null); then
    : # sourced, OK
else
    echo "ERROR: log-capture.sh is a library and must be sourced, not executed" >&2
    exit 2
fi

case "${LOG_CAPTURE_LOADED:-0}" in
    1) return 0 ;;
esac
LOG_CAPTURE_LOADED=1

###############################################################################
# internal: validation helpers (POSIX sh)
###############################################################################

# _lc_is_numeric FD
_lc_is_numeric() {
    case "${1:-}" in
        ""|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

###############################################################################
# log_capture_stream LEVEL
###############################################################################
log_capture_stream() {
    _lc_level="${1:-}"

    # --- misuse checks (façade context) --------------------------------
    # Contract requires a single-line misuse diagnostic and return 11
    # when required façade-provided context is missing/invalid.
    _lc_miss=""

    [ "${LOG_FACADE_ACTIVE:-}" = "1" ] || _lc_miss="${_lc_miss} LOG_FACADE_ACTIVE"
    [ -n "${LOG_SINK_FD:-}" ]          || _lc_miss="${_lc_miss} LOG_SINK_FD"
    [ -n "${LOG_MIN_LEVEL:-}" ]        || _lc_miss="${_lc_miss} LOG_MIN_LEVEL"
    [ -n "${_lc_level:-}" ]            || _lc_miss="${_lc_miss} LEVEL"

    if [ -n "${_lc_miss# }" ]; then
        echo "log-capture misuse: missing/invalid:${_lc_miss}" >&2
        return 11
    fi

    # Validate LOG_SINK_FD (numeric + usable FD for >&FD redirection).
    if ! _lc_is_numeric "${LOG_SINK_FD}"; then
        echo "log-capture misuse: invalid: LOG_SINK_FD (not numeric)" >&2
        return 11
    fi
    : >&"${LOG_SINK_FD}" 2>/dev/null || {
        echo "log-capture misuse: invalid: LOG_SINK_FD (unusable FD)" >&2
        return 11
    }

    # NOTE:
    # - Do NOT validate LOG_MIN_LEVEL or LEVEL semantics here.
    # - Formatter owns level semantics and returns:
    #   0 success, 4 suppressed, 10 operational failure, 11 misuse (bad MIN_LEVEL).

    # --- main capture loop ---------------------------------------------
    #
    # Read stdin line-by-line, preserving empty lines.
    # POSIX-safe: no read -d, no arrays.
    #
    # set -u safety: initialize _lc_line before using it in the loop condition.
    _lc_line=""

    while IFS= read -r _lc_line || [ -n "$_lc_line" ]; do
        _lc_fmt=""

        # Build formatted line via log-format.
        # Redirect formatter stdout to /dev/null so nothing can leak toward job stdout
        # even if the formatter is buggy. It returns output via OUT_VAR.
        log_format_build_line \
            _lc_fmt \
            "${LOG_MIN_LEVEL}" \
            "${_lc_level}" \
            "${_lc_line}" \
            1>/dev/null
        _lc_rc=$?

        case "$_lc_rc" in
            0)
                # log-format returns a line WITHOUT trailing newline;
                # we add it here when writing to the sink.
                printf '%s\n' "$_lc_fmt" >&"${LOG_SINK_FD}" || {
                    echo "log-capture: write to sink failed" >&2
                    return 10
                }
                ;;
            4)
                # Suppressed by policy (non-failure).
                ;;
            10|11)
                # Propagate formatter operational failure / misuse.
                return "$_lc_rc"
                ;;
            *)
                echo "log-capture: unexpected formatter return code: $_lc_rc" >&2
                return 10
                ;;
        esac
    done

    return 0
}
