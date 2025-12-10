#!/bin/sh
# script-status-report.sh
# Author: deadhedd
#
# Check the "latest" log for each script and report any that exited
# with a non-zero code. Assumes each job has a file or symlink named:
#   job_name-latest
# pointing to its most recent log file.
#
# Exit status:
#   0 - no failures detected
#   1 - one or more failures found

# Where logs & latest pointers live
LOG_ROOT="/home/obsidian/logs"

LC_ALL=C
LANG=C
export LC_ALL LANG

extract_exit_code() {
    log_file=$1
    # Extract the last exit=N found in the log
    sed -n 's/.*exit=\([0-9][0-9]*\).*/\1/p' "$log_file" 2>/dev/null | tail -n 1
}

found_failures=0

# Capture the list of *-latest entries first so the loop runs in the main shell
list_file=$(mktemp "${TMPDIR:-/tmp}/script-status-latest.XXXXXX") || exit 1

find "$LOG_ROOT" -name '*-latest' 2>/dev/null >"$list_file"

while IFS= read -r link; do
    [ -n "$link" ] || continue

    # Must exist (follow symlink transparently)
    [ -e "$link" ] || continue

    base=$(basename "$link")
    job=${base%-latest}
    [ -n "$job" ] || job="(unknown)"

    log_file=$link

    exit_code=$(extract_exit_code "$log_file")

    # Skip logs without exit info
    [ -n "$exit_code" ] || continue

    # Skip successful runs
    if [ "$exit_code" = "0" ]; then
        continue
    fi

    printf 'FAIL: job=%s exit_code=%s log=%s\n' \
        "$job" "$exit_code" "$log_file"

    found_failures=1
done <"$list_file"

rm -f "$list_file"

exit "$found_failures"
