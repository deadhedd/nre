#!/bin/sh
# utils/core/script-status-report.sh — generate a simple status report for script failures
# Author: deadhedd
# License: MIT
set -eu

# Where logs & latest symlinks live
LOG_ROOT="${LOG_ROOT:-/home/obsidian/logs}"

LC_ALL=C
LANG=C
export LC_ALL LANG

extract_exit_code() {
    log_file=$1
    # Extract the last exit=N found in the log
    sed -n 's/.*exit=\([0-9][0-9]*\).*/\1/p' "$log_file" 2>/dev/null | tail -n 1
}

found_flag=$(mktemp "${TMPDIR:-/tmp}/script-status-fail.XXXXXX") || exit 1
rm -f "$found_flag" 2>/dev/null

# Find all "*-latest" symlinks under LOG_ROOT
find "$LOG_ROOT" -type l -name '*-latest' 2>/dev/null | while IFS= read -r link; do
    [ -L "$link" ] || continue

    # Job name = basename without "-latest"
    base=$(basename "$link")
    job=${base%-latest}
    [ -n "$job" ] || job="(unknown)"

    # The symlink itself points to the latest log; we can just read it directly.
    log_file=$link

    exit_code=$(extract_exit_code "$log_file")

    # Skip logs without exit info
    [ -n "$exit_code" ] || continue

    # Skip successful runs
    [ "$exit_code" = "0" ] && continue

    printf 'FAIL: job=%s exit_code=%s log=%s\n' \
        "$job" "$exit_code" "$log_file"

    : >"$found_flag"
done

if [ -f "$found_flag" ]; then
    rm -f "$found_flag"
    exit 1
fi

exit 0
