#!/bin/sh
# script-status-report.sh
# Author: deadhedd
#
# Scan all "*-latest.log" job logs, summarize their latest exit codes and
# warn/err patterns, and write a markdown status report into the Obsidian vault.
#
# Exit status:
#   0 - no failures detected
#   1 - one or more failures found

set -eu
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd -P)
job_wrap="$repo_root/utils/core/job-wrap.sh"
script_path="$script_dir/$(basename -- "$0")"

if [ "${JOB_WRAP_ACTIVE:-0}" != "1" ] && [ -x "$job_wrap" ]; then
  JOB_WRAP_ACTIVE=1 exec /bin/sh "$job_wrap" "$script_path" "$@"
fi

# ------------------------------------------------------------------------------
# Logging (wrapper-first; bootstrap only if not wrapped)
# ------------------------------------------------------------------------------

log_bootstrap_if_needed() {
  # If job-wrap already sourced log.sh and initialized logging, do nothing.
  if [ "${LOG_HELPER_LOADED:-0}" -eq 1 ] && [ -n "${LOG_FILE:-}" ]; then
    return 0
  fi

  # Direct-run (best-effort): source log.sh from repo and start/finish lifecycle.
  core_dir="$repo_root/utils/core"
  LOG_HELPER_DIR=${LOG_HELPER_DIR:-$core_dir}
  LOG_HELPER_PATH=${LOG_HELPER_PATH:-$LOG_HELPER_DIR/log.sh}
  export LOG_HELPER_DIR LOG_HELPER_PATH

  # shellcheck source=/dev/null
  . "$LOG_HELPER_PATH" || {
    printf 'ERR failed to source log helper (%s)\n' "$LOG_HELPER_PATH" >&2
    exit 2
  }

  log_start_job "script-status-report" \
    "cwd=$(pwd)" \
    "user=$(id -un 2>/dev/null || printf unknown)" \
    "path=${PATH:-}" \
    "argv=$(printf '%s ' "$0" "$@")"

  trap 'st=$?; log_finish_job "$st"; exit "$st"' EXIT HUP INT TERM
}

log_bootstrap_if_needed "$@"

# Where logs & latest pointers live
LOG_ROOT="/home/obsidian/logs"

# Where to write the markdown report (Obsidian vault)
VAULT_PATH="/home/obsidian/vaults/Main"
REPORT_NOTE="$VAULT_PATH/Server Logs/Script Status Report.md"

LC_ALL=C
LANG=C
export LC_ALL LANG

log_info "status-report: begin"
log_info "status-report: JOB_WRAP_ACTIVE=${JOB_WRAP_ACTIVE:-0}"
log_info "status-report: LOG_FILE=${LOG_FILE:-<unset>}"
log_info "status-report: LOG_LATEST_LINK=${LOG_LATEST_LINK:-<unset>}"
log_info "status-report: scan_root=$LOG_ROOT"
log_info "status-report: report_note=$REPORT_NOTE"

if [ -n "${LOG_LATEST_LINK:-}" ]; then
  if ls -l "$LOG_LATEST_LINK" >/dev/null 2>&1; then
    log_info "status-report: wrapper_latest_before=$(ls -l "$LOG_LATEST_LINK" 2>/dev/null | tr '\n' ' ')"
  else
    log_warn "status-report: wrapper_latest_missing_or_unreadable=$LOG_LATEST_LINK"
  fi
fi

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

# Count lines matching an ERE (case-insensitive).
# Returns 0 if file unreadable/missing.
count_matches_ci_ere() {
  file=$1
  ere=$2

  if [ ! -r "$file" ]; then
    printf '0'
    return 0
  fi

  # grep -i -E is POSIX-ish enough across the usual BSD/GNU set;
  # if grep fails (no matches), wc still prints 0.
  # shellcheck disable=SC2012
  grep -i -E "$ere" "$file" 2>/dev/null | wc -l | tr -d ' '
}

# Heuristic patterns (tune as your log format evolves).
# - WARN: matches WARN or WARNING as a token-ish thing
# - ERR : matches ERR, ERROR, or FATAL as a token-ish thing
WARN_ERE='^([0-9]{4}-[0-9]{2}-[0-9]{2}T[^ ]+[[:space:]]+)?(WARN|WARNING)([[:space:]:]|$)'
ERR_ERE='^([0-9]{4}-[0-9]{2}-[0-9]{2}T[^ ]+[[:space:]]+)?(ERR|ERROR|FATAL)([[:space:]:]|$)'

list_file=$(mktemp "${TMPDIR:-/tmp}/script-status-latest.XXXXXX") || exit 1
find "$LOG_ROOT" -name '*-latest.log' 2>/dev/null >"$list_file"
log_info "status-report: find_done list_file=$list_file"

tmp_report=$(mktemp "${TMPDIR:-/tmp}/script-status-report.XXXXXX") || {
  rm -f "$list_file"
  exit 1
}
trap 'rm -f "$tmp_report" "$list_file"' EXIT
log_info "status-report: tmp_report=$tmp_report"

{
  printf '# Script Status Report\n\n'
  printf 'Generated: %s\n\n' "$(now_utc)"
  printf 'This report summarizes the latest known status for each script, based on its `*-latest.log` log file.\n\n'
  printf '## Status Table\n\n'
  printf '| Script | Status | Exit Code | Warns | Errs | Log |\n'
  printf '|--------|--------|-----------|-------|------|-----|\n'
} >"$tmp_report"

total_jobs=0
ok_jobs=0
warn_jobs=0
fail_jobs=0
unknown_jobs=0
skipped_missing=0
skipped_unreadable=0

while IFS= read -r link; do
  [ -n "$link" ] || continue

  if [ ! -e "$link" ]; then
    skipped_missing=$((skipped_missing + 1))
    continue
  fi

  if [ ! -r "$link" ]; then
    skipped_unreadable=$((skipped_unreadable + 1))
    continue
  fi

  base=$(basename "$link")
  job=${base%-latest.log}
  [ -n "$job" ] || job="(unknown)"

  exit_code=$(extract_exit_code "$link")
  warn_count=$(count_matches_ci_ere "$link" "$WARN_ERE")
  err_count=$(count_matches_ci_ere "$link" "$ERR_ERE")

  # Default classification by exit code
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

  # Escalate based on log content:
  # - ERR/ERROR/FATAL lines count as a failure signal even if exit=0
  # - WARN lines are non-fatal but reflected in status as WARN if otherwise OK
  if [ "$err_count" -gt 0 ]; then
    # If it wasn't already a failure, promote and count as failure
    if [ "$status" != "FAIL" ]; then
      status="ERR"
      fail_jobs=$((fail_jobs + 1))
      # If we previously counted it as OK, undo that
      if [ "$exit_display" = "0" ]; then
        ok_jobs=$((ok_jobs - 1))
      elif [ "$exit_display" = "?" ]; then
        unknown_jobs=$((unknown_jobs - 1))
      fi
    fi
  elif [ "$warn_count" -gt 0 ]; then
    # Only promote to WARN if otherwise OK (don’t override FAIL/ERR/unknown)
    if [ "$status" = "OK" ]; then
      status="WARN"
      warn_jobs=$((warn_jobs + 1))
      ok_jobs=$((ok_jobs - 1))
    fi
  fi

  total_jobs=$((total_jobs + 1))

  log_info "scan_item: job=$job status=$status exit=$exit_display warns=$warn_count errs=$err_count latest=$link"

  printf '| %s | %s | %s | %s | %s | `%s` |\n' \
    "$(printf '%s' "$job" | escape_md)" \
    "$(printf '%s' "$status" | escape_md)" \
    "$(printf '%s' "$exit_display" | escape_md)" \
    "$(printf '%s' "$warn_count" | escape_md)" \
    "$(printf '%s' "$err_count" | escape_md)" \
    "$(printf '%s' "$link" | escape_md)" \
    >>"$tmp_report"
done <"$list_file"

log_info "status-report: scan_summary total=$total_jobs ok=$ok_jobs warn=$warn_jobs fail=$fail_jobs unknown=$unknown_jobs skipped_missing=$skipped_missing skipped_unreadable=$skipped_unreadable"

if [ "$total_jobs" -eq 0 ]; then
  printf '\n_No jobs found under `%s`._\n' "$LOG_ROOT" >>"$tmp_report"
else
  printf '\n---\n\n' >>"$tmp_report"
  printf 'Summary: %d job(s) total — %d OK, %d WARN, %d FAIL/ERR, %d unknown.\n' \
    "$total_jobs" "$ok_jobs" "$warn_jobs" "$fail_jobs" "$unknown_jobs" >>"$tmp_report"
fi

report_dir=$(dirname "$REPORT_NOTE")
[ -d "$report_dir" ] || mkdir -p "$report_dir" || exit 1

log_info "status-report: write_begin report_dir=$report_dir"
cat "$tmp_report" >"$REPORT_NOTE"
bytes=$(wc -c <"$REPORT_NOTE" 2>/dev/null | tr -d ' ' || printf '?')
lines=$(wc -l <"$REPORT_NOTE" 2>/dev/null | tr -d ' ' || printf '?')
log_info "status-report: write_done bytes=$bytes lines=$lines"

# Fail the run if any failures (non-zero exit or ERR patterns) were found
if [ "$fail_jobs" -gt 0 ]; then
  log_warn "status-report: exit=1 (fail_jobs=$fail_jobs)"
  exit 1
fi

log_info "status-report: exit=0"
exit 0
