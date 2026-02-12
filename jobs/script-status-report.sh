#!/bin/sh
# jobs/script-status-report.sh
# Leaf job (wrapper required)
#
# Version: 1.0
# Status: contract-aligned (leaf template)
#
# Scan all "*-latest.log" job logs, summarize their latest exit codes and
# warn/err patterns, and write a markdown status report into the Obsidian vault.
#
# Author: deadhedd
# License: MIT
# shellcheck shell=sh

set -eu

###############################################################################
# Logging (leaf responsibility: emit correctly-formatted messages to stderr)
###############################################################################

log_debug() { printf '%s\n' "DEBUG: $*" >&2; }
log_info()  { printf '%s\n' "INFO: $*"  >&2; }
log_warn()  { printf '%s\n' "WARN: $*"  >&2; }
log_error() { printf '%s\n' "ERROR: $*" >&2; }

###############################################################################
# Resolve paths
###############################################################################

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
wrap="$script_dir/../engine/wrap.sh"

case "$0" in
  /*) script_path=$0 ;;
  *)  script_path=$script_dir/${0##*/} ;;
esac

script_path=$(
  CDPATH= cd "$(dirname "$script_path")" && \
  d=$(pwd) && \
  printf '%s/%s\n' "$d" "${script_path##*/}"
) || {
  log_error "failed to canonicalize script path: $script_path"
  exit 127
}

###############################################################################
# Self-wrap (minimal, dumb, contract-aligned)
###############################################################################

if [ "${JOB_WRAP_ACTIVE:-0}" != "1" ]; then
  if [ ! -x "$wrap" ]; then
    log_error "leaf wrap: wrapper not found/executable: $wrap"
    exit 127
  fi
  log_info "leaf wrap: exec wrapper: $wrap"
  exec "$wrap" "$script_path" ${1+"$@"}
else
  log_debug "leaf wrap: wrapper active; executing leaf"
fi

###############################################################################
# Engine libs (wrapped path only)
###############################################################################

if [ -z "${REPO_ROOT:-}" ]; then
  log_error "REPO_ROOT not set (wrapper required)"
  exit 127
fi
case "$REPO_ROOT" in
  /*) : ;;
  *) log_error "REPO_ROOT not absolute: $REPO_ROOT"; exit 127 ;;
esac
repo_root=$REPO_ROOT

lib_dir=$repo_root/engine/lib
periods_lib=$lib_dir/periods.sh
datetime_lib=$lib_dir/datetime.sh

if [ ! -r "$periods_lib" ]; then
  log_error "periods lib not found/readable: $periods_lib"
  exit 127
fi
# shellcheck source=/dev/null
. "$periods_lib" || {
  log_error "failed to source periods lib: $periods_lib"
  exit 127
}

if [ ! -r "$datetime_lib" ]; then
  log_error "datetime lib not found/readable: $datetime_lib"
  exit 127
fi
# shellcheck source=/dev/null
. "$datetime_lib" || {
  log_error "failed to source datetime lib: $datetime_lib"
  exit 127
}

###############################################################################
# Argument parsing (template scaffold; customized for this job)
###############################################################################

usage() {
  cat <<'EOF_USAGE'
Usage: script-status-report.sh [--output <path>] [--dry-run] [--force]

Options:
  --output <path>   Output file path (absolute).
                    Default: <VAULT_ROOT>/Server Logs/Script Status Report.md
  --dry-run         Emit report to stdout instead of writing a file.
  --force           Overwrite existing files if present.
  --help            Show this message.
EOF_USAGE
}

output_path=""
dry_run=0
force=0

while [ $# -gt 0 ]; do
  case "$1" in
    --output)
      [ $# -ge 2 ] || { printf 'ERROR: missing value for --output\n' >&2; usage >&2; exit 2; }
      output_path=$2
      shift 2
      ;;
    --force)
      force=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'ERROR: unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

###############################################################################
# Job logic
###############################################################################

###############################################################################
# Compute anchor artifact path (result_ref)
###############################################################################

if [ -z "${VAULT_ROOT:-}" ]; then
  log_error "VAULT_ROOT not set (wrapper required)"
  exit 127
fi
artifact_root=$VAULT_ROOT

# Default report location inside the vault.
default_report="$artifact_root/Server Logs/Script Status Report.md"

if [ -z "$output_path" ]; then
  result_ref=$default_report
else
  case "$output_path" in
    */)
      log_error "internal: --output ends with '/': $output_path"
      exit 2
      ;;
  esac
  case "$output_path" in
    /*) result_ref=$output_path ;;
    *)  log_error "--output must be an absolute path: $output_path"; exit 2 ;;
  esac
fi

if [ -z "$result_ref" ]; then
  log_error "internal: result_ref empty"
  exit 127
fi
case "$result_ref" in
  */) log_error "internal: result_ref ends with '/': $result_ref"; exit 2 ;;
esac

###############################################################################
# Helpers (template-standard)
###############################################################################

write_atomic_file() {
  _dest=$1
  _tmp_dir=${_dest%/*}
  _tmp="${_tmp_dir}/${_dest##*/}.tmp.$$"

  if ! mkdir -p "$_tmp_dir"; then
    log_error "failed to create artifact directory: $_tmp_dir"
    exit 1
  fi

  (
    trap 'rm -f "$_tmp"' HUP INT TERM 0
    if ! cat >"$_tmp"; then
      exit 1
    fi
    if ! mv "$_tmp" "$_dest"; then
      exit 1
    fi
    trap - HUP INT TERM 0
    exit 0
  ) || {
    log_error "failed atomic write: $_dest"
    rm -f "$_tmp" 2>/dev/null || true
    exit 1
  }
}

###############################################################################
# Reporter implementation
###############################################################################

# Where logs & latest pointers live (wrapper may export LOG_ROOT; keep old default)
LOG_ROOT=${LOG_ROOT:-/home/obsidian/logs}

# Local timestamp for report
now_local() { dt_now_local_iso_no_tz; }

extract_exit_code() {
  log_file=$1
  # New wrapper format: leaf rc is emitted explicitly as:
  #   "... WRAP: leaf: rc=0"
  #
  # We intentionally ignore other rc= tokens (log-init, helper_rc, etc).
  sed -n 's/.*WRAP: leaf: rc=\([0-9][0-9]*\).*/\1/p' "$log_file" 2>/dev/null | tail -n 1
}

escape_md() {
  tr '\n' ' ' | sed 's/|/\\|/g'
}

count_matches_ci_ere() {
  file=$1
  ere=$2

  if [ ! -r "$file" ]; then
    printf '0'
    return 0
  fi

  grep -i -E "$ere" "$file" 2>/dev/null | wc -l | tr -d ' '
}

# Double-status ("INFO INFO:") is not required for detection; treat anything after
# the first level token as message content. However, modern logs use a space
# timestamp (not ISO T), so match the first level token after the timestamp+zone.
WARN_ERE='^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2}[[:space:]]+\[[^]]*\][[:space:]]+(WARN|WARNING)([[:space:]]|$)'
ERR_ERE='^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2}[[:space:]]+\[[^]]*\][[:space:]]+(ERR|ERROR|FATAL)([[:space:]]|$)'

generate_report() {
  # Generates markdown to stdout.
  # Uses temp list file for log discovery, cleaned via local trap.
  list_file=$(mktemp "${TMPDIR:-/tmp}/script-status-latest.XXXXXX") || return 1
  cleanup_list() { rm -f "$list_file" 2>/dev/null || true; }
  trap 'cleanup_list' HUP INT TERM 0

  find "$LOG_ROOT" -name '*-latest.log' 2>/dev/null >"$list_file" || true

  link_count=$(wc -l <"$list_file" | tr -d ' ')

  total_jobs=0
  ok_jobs=0
  warn_jobs=0
  fail_jobs=0
  unknown_jobs=0
  skipped_missing=0
  skipped_unreadable=0

  printf '# Script Status Report\n\n'
  printf 'Generated: %s\n\n' "$(now_local)"
  printf 'This report summarizes the latest known status for each script, based on its `*-latest.log` log file.\n\n'
  printf 'LOG_ROOT: `%s`\n\n' "$LOG_ROOT"
  printf '## Status Table\n\n'
  printf '| Script | Status | Exit Code | Warns | Errs | Log |\n'
  printf '|--------|--------|-----------|-------|------|-----|\n'

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

    if [ "$err_count" -gt 0 ]; then
      if [ "$status" != "FAIL" ]; then
        status="ERR"
        fail_jobs=$((fail_jobs + 1))
        [ "$exit_display" = "0" ] && ok_jobs=$((ok_jobs - 1))
        [ "$exit_display" = "?" ] && unknown_jobs=$((unknown_jobs - 1))
      fi
    elif [ "$warn_count" -gt 0 ]; then
      if [ "$status" = "OK" ]; then
        status="WARN"
        warn_jobs=$((warn_jobs + 1))
        ok_jobs=$((ok_jobs - 1))
      fi
    fi

    total_jobs=$((total_jobs + 1))

    printf '| %s | %s | %s | %s | %s | `%s` |\n' \
      "$(printf '%s' "$job" | escape_md)" \
      "$(printf '%s' "$status" | escape_md)" \
      "$(printf '%s' "$exit_display" | escape_md)" \
      "$(printf '%s' "$warn_count" | escape_md)" \
      "$(printf '%s' "$err_count" | escape_md)" \
      "$(printf '%s' "$link" | escape_md)"
  done <"$list_file"

  if [ "$total_jobs" -eq 0 ]; then
    printf '\n_No jobs found under `%s`._\n' "$LOG_ROOT"
  else
    printf '\n---\n\n'
    printf 'Summary: %d job(s) total — %d OK, %d WARN, %d FAIL/ERR, %d unknown.\n' \
      "$total_jobs" "$ok_jobs" "$warn_jobs" "$fail_jobs" "$unknown_jobs"
  fi

  if [ "$skipped_missing" -gt 0 ] || [ "$skipped_unreadable" -gt 0 ]; then
    printf '\n\nNotes: skipped %d missing and %d unreadable `*-latest.log` path(s).\n' \
      "$skipped_missing" "$skipped_unreadable"
  fi

  # Expose failure count to caller via stdout-only? No. Caller will recompute.
  # We return 0 here; caller will decide success/failure by re-parsing or by
  # re-running the counts. To avoid a second scan, we instead echo a marker line
  # that caller can parse from the generated output.
  printf '\n<!-- reporter:fail_jobs=%d -->\n' "$fail_jobs"

  trap - HUP INT TERM 0
  cleanup_list
  return 0
}

###############################################################################
# Overwrite guards
###############################################################################

if [ -f "$result_ref" ] && [ "$force" -ne 1 ] && [ "$dry_run" -ne 1 ]; then
  log_error "refusing to overwrite existing file: $result_ref (use --force)"
  exit 1
fi

###############################################################################
# Dry-run
###############################################################################

if [ "$dry_run" -eq 1 ]; then
  if [ -n "$output_path" ]; then
    log_warn "--dry-run ignores --output: $output_path"
  fi
  if [ "$force" -eq 1 ]; then
    log_warn "--dry-run ignores --force"
  fi
  generate_report || {
    log_error "failed to generate report"
    exit 1
  }
  exit 0
fi

###############################################################################
# Write anchor artifact (atomic; contractual)
###############################################################################

log_info "Generating script status report"
log_debug "LOG_ROOT=$LOG_ROOT"
log_info "Writing report to: $result_ref"

# Generate once, atomically write, and capture fail_jobs from marker.
tmp_body=$(mktemp "${TMPDIR:-/tmp}/script-status-report-body.XXXXXX") || {
  log_error "failed to create temp body file"
  exit 1
}
cleanup_body() { rm -f "$tmp_body" 2>/dev/null || true; }
trap 'cleanup_body' HUP INT TERM 0

if ! generate_report >"$tmp_body"; then
  log_error "failed to generate report content"
  exit 1
fi

# Parse marker for fail_jobs (single-source-of-truth: the run we just generated)
fail_jobs_parsed=$(sed -n 's/^<!-- reporter:fail_jobs=\([0-9][0-9]*\) -->$/\1/p' "$tmp_body" | tail -n 1)
case "${fail_jobs_parsed:-}" in
  "" ) fail_jobs_parsed=0 ;;
  * ) : ;;
esac

# Final atomic write
write_atomic_file "$result_ref" <"$tmp_body"

# Disarm temp cleanup
trap - HUP INT TERM 0
cleanup_body

###############################################################################
# Commit registration (contractual; multi-artifact)
###############################################################################

if [ -n "${COMMIT_LIST_FILE:-}" ]; then
  if ! printf '%s\n' "$result_ref" >>"$COMMIT_LIST_FILE" 2>/dev/null; then
    log_warn "failed to append to COMMIT_LIST_FILE: $COMMIT_LIST_FILE"
  fi
fi

###############################################################################
# Diagnostics
###############################################################################

log_info "Produced artifact: $result_ref"

# Job exit policy:
# - Exit 1 if any failures detected (non-zero exit or ERR patterns)
if [ "$fail_jobs_parsed" -gt 0 ]; then
  log_error "detected failed jobs: fail_jobs=$fail_jobs_parsed"
  exit 1
fi

exit 0
