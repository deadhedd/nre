#!/bin/sh
# jobs/script-status-report.sh
# Leaf job (wrapper required)
#
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
sync_latest_logs_job="$script_dir/helpers/sync-latest-logs-to-vault.sh"

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

# Contract: every leaf must declare cadence in stderr for freshness evaluation.
JOB_CADENCE=${JOB_CADENCE:-daily}
log_info "cadence=$JOB_CADENCE"

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
Usage: script-status-report.sh [--output <path>] [--dry-run]

Options:
  --output <path>   Output file path (absolute).
                    Default: <VAULT_ROOT>/Server Logs/Script Status Report.md
  --dry-run         Emit report to stdout instead of writing a file.
  --help            Show this message.
EOF_USAGE
}

output_path=""
dry_run=0

while [ $# -gt 0 ]; do
  case "$1" in
    --output)
      [ $# -ge 2 ] || { printf 'ERROR: missing value for --output\n' >&2; usage >&2; exit 2; }
      output_path=$2
      shift 2
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

run_sync_latest_logs_to_vault() {
  # Best-effort: refresh Obsidian "Latest Logs" markdown mirrors before we
  # emit a report that links to them.
  #
  # IMPORTANT:
  # This is a helper executable (not a leaf job). It MUST NOT self-wrap, and
  # it MUST NOT register commits itself. Instead, this wrapped leaf job
  # optionally registers the helper outputs in COMMIT_LIST_FILE.
  if [ ! -x "$sync_latest_logs_job" ]; then
    log_warn "sync helper not found/executable: $sync_latest_logs_job (skipping)"
    return 0
  fi

  log_info "Refreshing vault latest-log mirrors"
  log_debug "sync helper exec: $sync_latest_logs_job"

  tmp_written=$(mktemp "${TMPDIR:-/tmp}/sync-latest-logs.written.XXXXXX") || {
    log_warn "mktemp failed; running sync without commit registration"
    "$sync_latest_logs_job" >/dev/null || {
      rc=$?
      log_warn "sync-latest-logs helper failed (rc=$rc); continuing"
      return 0
    }
    return 0
  }

  cleanup_written() { rm -f "$tmp_written" 2>/dev/null || true; }
  trap 'cleanup_written' HUP INT TERM 0

  # Helper logs to stderr (captured by this job's wrapped log).
  # Helper writes list of written files to stdout; capture it for commit reg.
  if ! "$sync_latest_logs_job" --emit-written-list >"$tmp_written" 2>/dev/null; then
    rc=$?
    log_warn "sync-latest-logs helper failed (rc=$rc); continuing"
    trap - HUP INT TERM 0
    cleanup_written
    return 0
  fi

  # Parent leaf registers the helper's outputs for commit.
  if [ -n "${COMMIT_LIST_FILE:-}" ]; then
    if ! cat "$tmp_written" >>"$COMMIT_LIST_FILE" 2>/dev/null; then
      log_warn "failed to append sync outputs to COMMIT_LIST_FILE: $COMMIT_LIST_FILE"
    fi
  fi

  trap - HUP INT TERM 0
  cleanup_written
  return 0
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

extract_cadence() {
  log_file=$1
  # Contract: leaf MUST declare cadence. We accept tokens in the form:
  #   cadence=<value>
  # appearing anywhere in the log, and take the last occurrence.
  sed -n 's/.*[[:space:]]cadence=\([A-Za-z0-9_+-][A-Za-z0-9_+.-]*\).*/\1/p' "$log_file" 2>/dev/null | tail -n 1
}

extract_grace_token() {
  log_file=$1
  # Optional: grace window for freshness. Accept tokens in the form:
  #   grace=<n><unit>
  # where unit is one of: s, m, h, d
  # Take the last occurrence if multiple are present.
  sed -n 's/.*[[:space:]]grace=\([0-9][0-9]*[smhd]\).*/\1/p' "$log_file" 2>/dev/null | tail -n 1
}

grace_to_seconds() {
  # Convert "<n><unit>" (e.g. 6h) to seconds. Empty/invalid -> 0.
  _tok=${1-}
  [ -n "${_tok:-}" ] || { printf '%s\n' 0; return 0; }

  _n=$(printf '%s' "$_tok" | sed 's/[^0-9].*$//')
  _u=$(printf '%s' "$_tok" | sed 's/^[0-9][0-9]*//')

  case "${_n:-}" in
    ''|*[!0-9]*)
      printf '%s\n' 0
      return 0
      ;;
  esac

  case "$_u" in
    s) printf '%s\n' "$_n" ;;
    m) printf '%s\n' $((_n * 60)) ;;
    h) printf '%s\n' $((_n * 3600)) ;;
    d) printf '%s\n' $((_n * 86400)) ;;
    *)
      # Unknown unit -> ignore (no grace)
      printf '%s\n' 0
      ;;
  esac
}

extract_run_ts_local() {
  log_file=$1
  # Extract the first timestamp in the canonical log line prefix:
  #   "YYYY-MM-DD HH:MM:SS ..."
  # We capture only the "YYYY-MM-DD HH:MM:SS" portion (local time).
  sed -n 's/^\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}[[:space:]][0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}\).*/\1/p' "$log_file" 2>/dev/null | head -n 1
}

ts_local_to_epoch() {
  # Convert "YYYY-MM-DD HH:MM:SS" (local time) to epoch seconds using the
  # already-detected date backend from engine/lib/datetime.sh.
  _ts=${1-}
  [ -n "$_ts" ] || return 1

  case "${DT_DATE_BACKEND:-0}" in
    1)
      # BSD date
      "$DT_DATE_BIN" -j -f '%Y-%m-%d %H:%M:%S' "$_ts" '+%s' 2>/dev/null
      ;;
    2)
      # GNU date
      "$DT_DATE_BIN" -d "$_ts" '+%s' 2>/dev/null
      ;;
    *)
      return 1
      ;;
  esac
}

cadence_allowed_age_sec() {
  # Map cadence tokens -> allowed age in seconds before "stale".
  #
  # Semantics:
  # - Zero grace period.
  # - Stale means the job did not run within exactly one cadence interval.
  # - ad-hoc is not evaluated (prints empty).
  _c=${1-}
  case "$_c" in
    ad-hoc)    printf '%s' '' ;;
    hourly)    printf '%s' 3600 ;;
    daily)     printf '%s' 86400 ;;
    weekly)    printf '%s' 604800 ;;
    monthly)   printf '%s' 2592000 ;;
    quarterly) printf '%s' 7776000 ;;
    yearly)    printf '%s' 31536000 ;;
    *)
      # Unrecognized cadence token: indeterminate (prints "?" so caller can flag)
      printf '%s' '?'
      ;;
  esac
}

resolve_latest_target_abs() {
  # Given a *-latest.log path, attempt to resolve its symlink target to an
  # absolute path. If not a symlink or readlink fails, print nothing.
  _link=$1
  _dir=${_link%/*}

  _t=$(readlink "$_link" 2>/dev/null || true)
  [ -n "$_t" ] || return 0

  case "$_t" in
    /*) _abs=$_t ;;
    *)  _abs=$_dir/$_t ;;
  esac

  _abs=$(
    CDPATH= cd -- "${_abs%/*}" 2>/dev/null && \
    _d=$(pwd -P) && \
    printf '%s/%s\n' "$_d" "${_abs##*/}"
  ) || return 0

  printf '%s\n' "$_abs"
}

find_previous_completed_log() {
  # Best-effort: for a given <job>-latest.log, find the newest log file for
  # that job in the same directory EXCLUDING the current latest target.
  # Prints absolute path, or nothing if not found.
  _latest=$1
  _job=$2

  _latest_abs=$(resolve_latest_target_abs "$_latest")
  _search_dir=${_latest_abs%/*}
  [ -n "$_latest_abs" ] || _search_dir=${_latest%/*}

  # Collect candidates newest-first by mtime.
  # Exclude:
  #  - the symlink itself (<job>-latest.log)
  #  - the resolved latest target (current run)
  _cand=$(
    ls -1t "$_search_dir/$_job"*.log 2>/dev/null \
      | grep -v "/${_latest##*/}\$" \
      | { if [ -n "$_latest_abs" ]; then grep -v "^$_latest_abs\$"; else cat; fi; } \
      | head -n 1
  ) || true

  [ -n "${_cand:-}" ] || return 0

  _abs=$(
    CDPATH= cd -- "${_cand%/*}" 2>/dev/null && \
    _d=$(pwd -P) && \
    printf '%s/%s\n' "$_d" "${_cand##*/}"
  ) || return 0

  printf '%s\n' "$_abs"
}

compute_freshness() {
  # Inputs:
  #   $1 log_file
  #
  # Outputs (space-separated):
  #   cadence freshness age_sec_or_? allowed_sec_or_?/blank grace_sec
  #
  # freshness:
  #   fresh | late | stale | n/a | indeterminate
  _log=$1

  _cad=$(extract_cadence "$_log")
  if [ -z "$_cad" ]; then
    printf '%s\n' "? indeterminate ? ? 0"
    return 0
  fi

  _allowed_base=$(cadence_allowed_age_sec "$_cad")
  if [ "$_allowed_base" = "?" ]; then
    printf '%s\n' "$_cad indeterminate ? ? 0"
    return 0
  fi
  if [ -z "$_allowed_base" ]; then
    # ad-hoc (or explicitly non-evaluable)
    printf '%s\n' "$_cad n/a 0 0"
    return 0
  fi

  _ts=$(extract_run_ts_local "$_log")
  _run_epoch=$(ts_local_to_epoch "$_ts" || true)
  if [ -z "$_run_epoch" ]; then
    printf '%s\n' "$_cad indeterminate ? $_allowed_base 0"
    return 0
  fi

  _now=$(dt_now_epoch 2>/dev/null || true)
  if [ -z "$_now" ]; then
    printf '%s\n' "$_cad indeterminate ? $_allowed_base 0"
    return 0
  fi

  _age=$((_now - _run_epoch))
  if [ "$_age" -lt 0 ] 2>/dev/null; then
    # Clock skew; treat as indeterminate rather than "fresh".
    printf '%s\n' "$_cad indeterminate ? $_allowed_base 0"
    return 0
  fi

  _grace_tok=$(extract_grace_token "$_log")
  _grace_sec=$(grace_to_seconds "$_grace_tok")
  _allowed_total=$((_allowed_base + _grace_sec))

  if [ "$_age" -gt "$_allowed_total" ] 2>/dev/null; then
    printf '%s\n' "$_cad stale $_age $_allowed_total $_grace_sec"
    return 0
  fi

  # Within grace: "late" (expected for wake-triggered jobs like sleep summary).
  if [ "$_grace_sec" -gt 0 ] 2>/dev/null && [ "$_age" -gt "$_allowed_base" ] 2>/dev/null; then
    printf '%s\n' "$_cad late $_age $_allowed_total $_grace_sec"
  else
    printf '%s\n' "$_cad fresh $_age $_allowed_total $_grace_sec"
  fi
}

# Double-status ("INFO INFO:") is not required for detection; treat anything after
# the first level token as message content. However, modern logs use a space
# timestamp (not ISO T), so match the first level token after the timestamp+zone.
WARN_ERE='^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2}[[:space:]]+\[[^]]*\][[:space:]]+(WARN|WARNING)([[:space:]]|$)'
ERR_ERE='^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2}[[:space:]]+\[[^]]*\][[:space:]]+(ERR|ERROR|FATAL|UNDEF)([[:space:]]|$)'

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
  printf 'Note: the self row (`script-status-report`) reflects the **previous completed run** (the current run cannot accurately report itself).\n\n'
  printf 'LOG_ROOT: `%s`\n\n' "$LOG_ROOT"
  printf '## Status Table\n\n'
  printf '| Script | Status | Exit Code | Warns | Errs | Cadence | Fresh | Log |\n'
  printf '|--------|--------|-----------|-------|------|---------|-------|-----|\n'

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

    # Self-reporting note:
    # The wrapper repoints <job>-latest.log at run start, so the current run
    # cannot use its own latest link to assess itself. For the self row only,
    # evaluate the previous completed physical log file if available.
    eval_log=$link
    self_prev=0
    if [ "$job" = "script-status-report" ]; then
      prev_log=$(find_previous_completed_log "$link" "$job")
      if [ -n "${prev_log:-}" ] && [ -r "$prev_log" ]; then
        eval_log=$prev_log
        self_prev=1
      fi
    fi

    exit_code=$(extract_exit_code "$eval_log")
    warn_count=$(count_matches_ci_ere "$eval_log" "$WARN_ERE")
    err_count=$(count_matches_ci_ere "$eval_log" "$ERR_ERE")

    # Cadence/freshness (contract-mandated)
    freshness_line=$(compute_freshness "$eval_log")
    cadence=$(printf '%s\n' "$freshness_line" | awk '{print $1}')
    fresh_state=$(printf '%s\n' "$freshness_line" | awk '{print $2}')
    # age_sec and allowed_sec currently unused for display; kept for potential future debug
    # age_sec=$(printf '%s\n' "$freshness_line" | awk '{print $3}')
    # allowed_sec=$(printf '%s\n' "$freshness_line" | awk '{print $4}')
    # grace_sec=$(printf '%s\n' "$freshness_line" | awk '{print $5}')
    fresh_display=$fresh_state

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

    if [ "$self_prev" -eq 1 ]; then
      status="${status}(prev)"
    fi

    # Cadence / freshness precedence:
    # - Missing/unparseable cadence => unhealthy (contract: cadence missing is error)
    # - Stale => unhealthy (orthogonal to success/failure)
    #
    # These conditions contribute to fail_jobs (reporter marker).
    if [ "$cadence" = "?" ]; then
      if [ "$status" = "OK" ]; then ok_jobs=$((ok_jobs - 1)); fi
      if [ "$status" = "WARN" ]; then warn_jobs=$((warn_jobs - 1)); fi
      if [ "$status" = "unknown" ]; then unknown_jobs=$((unknown_jobs - 1)); fi
      status="NO-CAD"
      fail_jobs=$((fail_jobs + 1))
      fresh_display="indeterminate"
    elif [ "$fresh_state" = "stale" ]; then
      if [ "$status" = "OK" ]; then ok_jobs=$((ok_jobs - 1)); fi
      if [ "$status" = "WARN" ]; then warn_jobs=$((warn_jobs - 1)); fi
      status="STALE"
      fail_jobs=$((fail_jobs + 1))
      fresh_display="stale"
    elif [ "$fresh_state" = "late" ]; then
      # Late-but-within-grace: keep status as-is; show state for visibility.
      fresh_display="late"
    elif [ "$fresh_state" = "indeterminate" ]; then
      if [ "$status" = "OK" ]; then ok_jobs=$((ok_jobs - 1)); fi
      if [ "$status" = "WARN" ]; then warn_jobs=$((warn_jobs - 1)); fi
      if [ "$status" = "unknown" ]; then unknown_jobs=$((unknown_jobs - 1)); fi
      status="FRESH?"
      fail_jobs=$((fail_jobs + 1))
    fi

    total_jobs=$((total_jobs + 1))

    if [ "$self_prev" -eq 1 ]; then
      # Link to the current latest mirror (in-progress), but disclose which
      # physical log file was evaluated for the "prev" status.
      log_link=$(printf '[[%s-latest|current]]<br>prev: %s' "$job" "${eval_log##*/}")
    else
      log_link=$(printf '[[%s-latest]]' "$job")
    fi

    printf '| %s | %s | %s | %s | %s | %s | %s | %s |\n' \
      "$(printf '%s' "$job" | escape_md)" \
      "$(printf '%s' "$status" | escape_md)" \
      "$(printf '%s' "$exit_display" | escape_md)" \
      "$(printf '%s' "$warn_count" | escape_md)" \
      "$(printf '%s' "$err_count" | escape_md)" \
      "$(printf '%s' "$cadence" | escape_md)" \
      "$(printf '%s' "$fresh_display" | escape_md)" \
      "$(printf '%s' "$log_link" | escape_md)"
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
# Dry-run
###############################################################################

if [ "$dry_run" -eq 1 ]; then
  if [ -n "$output_path" ]; then
    log_warn "--dry-run ignores --output: $output_path"
  fi
  generate_report || {
    log_error "failed to generate report"
    exit 1
  }
  exit 0
fi

###############################################################################
# Ensure vault mirrors exist (so report links resolve)
###############################################################################

run_sync_latest_logs_to_vault

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

exit 0
