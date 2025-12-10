#!/bin/sh
# script-status-report.sh
# Author: deadhedd
#
# Scan all "*-latest" job logs, summarize their latest exit codes,
# and write a markdown status report into the Obsidian vault.
#
# Exit status:
#   0 - no failures detected
#   1 - one or more failures found
set -eu

# Where logs & latest pointers live
LOG_ROOT="/home/obsidian/logs"

# Where to write the markdown report (Obsidian vault)
VAULT_PATH="/home/obsidian/vaults/Main"
REPORT_NOTE="$VAULT_PATH/Server Logs/Script Status Report.md"

LC_ALL=C
LANG=C
export LC_ALL LANG

now_utc() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

extract_exit_code() {
    log_file=$1
    sed -n 's/.*exit=\([0-9][0-9]*\).*/\1/p' "$log_file" 2>/dev/null | tail -n 1
}

escape_md() {
    tr '\n' ' ' | sed 's/|/\\|/g'
}

list_file=$(mktemp "${TMPDIR:-/tmp}/script-status-latest.XXXXXX") || exit 1
find "$LOG_ROOT" -name '*-latest' 2>/dev/null >"$list_file"

tmp_report=$(mktemp "${TMPDIR:-/tmp}/script-status-report.XXXXXX") || {
    rm -f "$list_file"
    exit 1
}
trap 'rm -f "$tmp_report" "$list_file"' EXIT

{
    printf '# Script Status Report\n\n'
    printf 'Generated: %s\n\n' "$(now_utc)"
    printf 'This report summarizes the latest known status for each script, based on its `*-latest` log file.\n\n'
    printf '## Status Table\n\n'
    printf '| Script | Status | Exit Code | Log |\n'
    printf '|--------|--------|-----------|-----|\n'
} >"$tmp_report"

total_jobs=0
ok_jobs=0
fail_jobs=0
unknown_jobs=0

while IFS= read -r link; do
    [ -n "$link" ] || continue
    [ -e "$link" ] || continue

    base=$(basename "$link")
    job=${base%-latest}
    [ -n "$job" ] || job="(unknown)"

    exit_code=$(extract_exit_code "$link")

    if [ -z "$exit_code" ]; then
        status="unknown"
        exit_display="?"
        unknown_jobs=$((unknown_jobs + 1))
    elif [ "$exit_code" = "0" ]; then
        status="OK"
        exit_display="0"
        ok_jobs=$((ok_jobs + 1))
    else
        status="FAIL"
        exit_display="$exit_code"
        fail_jobs=$((fail_jobs + 1))
    fi

    total_jobs=$((total_jobs + 1))

    printf '| %s | %s | %s | `%s` |\n' \
        "$(printf '%s' "$job" | escape_md)" \
        "$(printf '%s' "$status" | escape_md)" \
        "$(printf '%s' "$exit_display" | escape_md)" \
        "$(printf '%s' "$link" | escape_md)" \
        >>"$tmp_report"
done <"$list_file"

rm -f "$list_file"

if [ "$total_jobs" -eq 0 ]; then
    printf '\n_No jobs found under `%s`._\n' "$LOG_ROOT" >>"$tmp_report"
else
    printf '\n---\n\n' >>"$tmp_report"
    printf 'Summary: %d job(s) total — %d OK, %d FAIL, %d unknown.\n' \
        "$total_jobs" "$ok_jobs" "$fail_jobs" "$unknown_jobs" >>"$tmp_report"
fi

report_dir=$(dirname "$REPORT_NOTE")
[ -d "$report_dir" ] || mkdir -p "$report_dir" || exit 1

cat "$tmp_report" >"$REPORT_NOTE"

[ "$fail_jobs" -gt 0 ] && exit 1
exit 0
