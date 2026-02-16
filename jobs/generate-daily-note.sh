#!/bin/sh
# Generate a daily note markdown file that mirrors the legacy Node implementation.
#
# Leaf job (wrapper required). Uses /lib periods+datetime helpers (local time).
#
# Author: deadhedd
# License: MIT

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

# C1 bootstrap rule: wrapper location is assumed stable *relative to this file*
# for the initial self-wrap hop only. Once wrapped, REPO_ROOT (exported by the
# wrapper) becomes the source of truth for repo-relative paths.
wrap="$script_dir/../engine/wrap.sh"

# Prefer passing an absolute script path to the wrapper for sturdiness.
case "$0" in
  /*) script_path=$0 ;;
  *)  script_path=$script_dir/${0##*/} ;;
esac

# Canonicalize the final script path to avoid surprises (symlinks/cwd oddities).
# POSIX note: this resolves directory via cd+pwd; basename is preserved.
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

# engine/wrap.sh owns JOB_WRAP_ACTIVE; leaf does not set it.
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
# Cadence declaration (contract-required)
###############################################################################
#
# Contract:
# - Every leaf MUST declare a cadence token in stderr so status reporting can
#   evaluate freshness from the captured job log.
# - This must run in the wrapped execution path so it lands in the real log.
#
# Allowed tokens:
#   hourly | daily | weekly | monthly | quarterly | yearly | ad-hoc
JOB_CADENCE="daily"
log_info "cadence=$JOB_CADENCE"

###############################################################################
# Engine libs (wrapped path only)
###############################################################################

# Wrapper contract: REPO_ROOT is provided (absolute) once wrapped.
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

# Periods (days / weeks / months / quarters)
if [ ! -r "$periods_lib" ]; then
  log_error "periods lib not found/readable: $periods_lib"
  exit 127
fi
# shellcheck source=/dev/null
. "$periods_lib" || {
  log_error "failed to source periods lib: $periods_lib"
  exit 127
}

# Datetime (local-time only)
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
# Argument parsing (template scaffold preserved + --force extension)
###############################################################################

usage() {
  cat <<'EOF_USAGE'
Usage: generate-daily-note.sh [--output <path>] [--dry-run] [--force]

Options:
  --output <path>   Output file path (absolute). Defaults to today's daily note in the vault.
  --dry-run         Emit the main daily note content to stdout instead of writing files.
  --force           Overwrite existing files (main note + subnotes) if present.
  --help            Show this message.
EOF_USAGE
}

force=0
dry_run=0
output_path=""

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

# Ensure common tools are found even under cron (put /usr/local/bin first)
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

# Artifact root:
# - Must be provided by wrapper.
if [ -z "${VAULT_ROOT:-}" ]; then
  log_error "VAULT_ROOT not set (wrapper required)"
  exit 127
fi
artifact_root=$VAULT_ROOT

# Internal helper layout (repo-local)
helpers_dir="$repo_root/jobs/helpers"

day_plan_script="$helpers_dir/generate-day-plan.sh"
celestial_timings_script="$helpers_dir/generate-celestial-timings.sh"
f1_script="$helpers_dir/f1-schedule-and-standings.sh"
f1_dashboard_helper="$helpers_dir/update-f1-dashboard.sh"
finances_callout_script="$helpers_dir/daily-finances-callout.sh"

###############################################################################
# Compute primary output path (result_ref)
###############################################################################

# Default vault structure (within VAULT_ROOT)
periodic_dir="${artifact_root%/}/Periodic Notes"
daily_note_dir="${periodic_dir%/}/Daily Notes"

today=$(pr_today)
current_date_parts=$(pr_date_parts) # "YYYY MM DD"
year=${current_date_parts%% *}
month_day=${current_date_parts#* }
month=${month_day%% *}
day=${month_day#* }

week_tag=$(pr_week_tag_current)
month_tag=$(pr_month_tag_current)
quarter_tag_iso=$(pr_quarter_tag_iso)

yesterday=$(pr_yesterday)
tomorrow=$(pr_tomorrow)

if [ -z "$output_path" ]; then
  result_ref="${daily_note_dir%/}/${today}.md"
else
  case "$output_path" in
    */)
      log_error "internal: --output ends with '/': $output_path"
      exit 2
      ;;
  esac
  # Contract: --output must be an absolute path.
  case "$output_path" in
    /*) result_ref="$output_path" ;;
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
# Helpers (job-specific; contract-preserving)
###############################################################################

write_atomic_file() {
  _dest=$1
  _tmp_dir=${_dest%/*}
  _tmp="${_tmp_dir}/${_dest##*/}.tmp.$$"

  if ! mkdir -p "$_tmp_dir"; then
    log_error "failed to create artifact directory: $_tmp_dir"
    exit 1
  fi

  # Contain trap scope to a subshell so we don't stomp outer traps.
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

build_finances_callout() {
  if [ ! -r "$finances_callout_script" ]; then
    log_warn "finances callout script not found: $finances_callout_script"
    return 0
  fi
  if _out=$(sh "$finances_callout_script" "$year" "$month" "$day" 2>/dev/null); then
    printf '%s' "$_out"
    return 0
  fi
  _rc=$?
  log_warn "finances callout script failed rc=$_rc; skipping finances section"
  return 0
}

###############################################################################
# Dry run behavior (template contract)
###############################################################################

generate_main_note() {
  finances_callout=$(build_finances_callout)

  time_blocks_nav=$(cat <<EOF_TB
### 🕑 Time Blocks

 [[Periodic Notes/Daily Notes/Subnotes/${today} - Wake Up|Wake Up]] · [[Periodic Notes/Daily Notes/Subnotes/${today} - Morning|Morning]] · [[Periodic Notes/Daily Notes/Subnotes/${today} - Afternoon|Afternoon]] · [[Periodic Notes/Daily Notes/Subnotes/${today} - Evening|Evening]] · [[Periodic Notes/Daily Notes/Subnotes/${today} - Night|Night]]

### 📅 Periodic Notes

[[Periodic Notes/Weekly Notes/${week_tag}|This Week]] · [[Periodic Notes/Monthly Notes/${month_tag}|This Month]] · [[Periodic Notes/Quarterly Notes/${quarter_tag_iso}|This Quarter]] · [[Periodic Notes/Yearly Notes/${year}|This Year]]

### 🔗 Links

[[Weekly Routine]] · [[Consider Johnie]] · [[Daily Note Template]] · [[Daily Plan]] · [[Workout Schedule]]
EOF_TB
)

  navigation_callout=$(cat <<EOF_NAVIGATION
> [!note]+ 🗺️ Navigation
$(printf '%s\n' "$time_blocks_nav" | sed 's/^/> /')
EOF_NAVIGATION
)

  pagan_timings_text=""
  if [ -r "$celestial_timings_script" ]; then
    if pagan_timings_text=$(sh "$celestial_timings_script" 2>/dev/null); then
      : # ok
    else
      _rc=$?
      log_warn "celestial timings script failed rc=$_rc; using fallback"
      pagan_timings_text=""
    fi
  else
    log_warn "celestial timings script not found: $celestial_timings_script"
  fi
  if [ -z "${pagan_timings_text:-}" ]; then
    pagan_timings_text="### 🌌 Celestial Timings
_Celestial timings unavailable._"
  fi

  daily_context_callout=$(cat <<EOF_DAILY_CONTEXT
> [!info]+ 🌅 Daily Context
> ### Sleep
> ![[Sleep Data/${today} Sleep Summary#Sleep Advice]]
>
> ### 🌤️ Yard Work Suitability
> <!-- yard-work-check -->
>
$(printf '%s\n' "$pagan_timings_text" | sed 's/^/> /')
EOF_DAILY_CONTEXT
)

  direction_callout=$(cat <<EOF_DIRECTION
> [!tip]+ 🎯 Direction & Intent
> ### ![[Yearly theme]]
>
> ### ![[Season Theme]]
>
> ### ![[Periodic Notes/Weekly Notes/${week_tag}#🎯 Weekly Goal]]
EOF_DIRECTION
)

  execution_callout=$(cat <<'EOF_EXECUTION'
> [!todo]+ ✅ Execution
> ### 🔁 Recurring Today
> [[Recurring Tasks]]
> ```tasks
> not done
> happens on or before today
> sort by happens
> ```
>
> ### 📌 Focus Buckets
>
> - [[Stand on Business]]
> - [[Quick Wins]]
> - [[Comms Queue]]
> - [[Device Config]]
> - [[Someday/Maybe]]
EOF_EXECUTION
)

  f1_callout=$(cat <<EOF_F1
> [!info]+ 🏎️ F1 Info
>
> ![[Reference/Dashboards/Formula 1]]
EOF_F1
)

  daily_plan_intro_section=""
  if [ -r "$day_plan_script" ]; then
    if _day_plan_output=$(sh "$day_plan_script" 2>/dev/null); then
      _intro=$(
        printf '%s\n' "$_day_plan_output" | awk '
          /^# Daily Plan - / {in_today=1; next}
          in_today && /^## Preview of Tomorrow:/ {exit}
          in_today {
            if (!day && /^##[[:space:]]+/) {
              line = $0
              sub(/^##[[:space:]]+/, "", line)
              day = line
              next
            }
            if (!focus && /^###[[:space:]]+/) {
              line = $0
              sub(/^###[[:space:]]+/, "", line)
              focus = line
            }
          }
          END {
            if (day && focus) {
              printf("## %s (%s)\n", day, focus)
            } else if (day) {
              printf("## %s\n", day)
            } else if (focus) {
              printf("## %s\n", focus)
            }
          }
        '
      )
      if [ -n "${_intro:-}" ]; then
        daily_plan_intro_section=$(printf '%s\n\n' "$_intro")
      fi
    else
      _rc=$?
      log_warn "daily plan script failed rc=$_rc; skipping intro"
    fi
  else
    log_warn "daily plan script not found; skipping intro"
  fi

  cat <<EOF_NOTE
---
tags:
  - matter/daily-notes
---
<< [[Periodic Notes/Daily Notes/${yesterday}|${yesterday}]] | [[Periodic Notes/Daily Notes/${tomorrow}|${tomorrow}]] >>

${daily_plan_intro_section}

${navigation_callout}

${daily_context_callout}

${direction_callout}

${execution_callout}

${finances_callout}

${f1_callout}
EOF_NOTE
}

if [ "$dry_run" -eq 1 ]; then
  if [ -n "$output_path" ]; then
    log_warn "--dry-run ignores --output: $output_path"
  fi

  # Tell the wrapper/commit layer to "dry-run" commit behavior too (no staging/commit),
  # so it can suppress required-commit warnings and optionally print a preview.
  # Wrapper/commit scripts must honor COMMIT_DRY_RUN=1.
  export COMMIT_DRY_RUN=1

  log_warn "--dry-run emits only the main daily note to stdout (no subnotes/dashboard writes)"
  generate_main_note
  exit 0
fi

###############################################################################
# Overwrite guards (external boundary: filesystem state)
###############################################################################

time_block_subnotes_dir="${daily_note_dir%/}/Subnotes"
f1_dashboard_note="Reference/Dashboards/Formula 1"
f1_dashboard_path="${artifact_root%/}/${f1_dashboard_note}.md"

# Main note
if [ -f "$result_ref" ] && [ "$force" -ne 1 ]; then
  log_error "refusing to overwrite existing file: $result_ref (use --force)"
  exit 1
fi

# Subnotes
for _subnote in "Wake Up" "Morning" "Afternoon" "Evening" "Night"; do
  _subnote_path="${time_block_subnotes_dir%/}/${today} - ${_subnote}.md"
  if [ -f "$_subnote_path" ] && [ "$force" -ne 1 ]; then
    log_error "refusing to overwrite existing subnote: $_subnote_path (use --force)"
    exit 1
  fi
done

###############################################################################
# F1 dashboard handling (side-effect artifact; best-effort)
###############################################################################

if [ -r "$f1_dashboard_helper" ]; then
  if sh "$f1_dashboard_helper" --dashboard-path "$f1_dashboard_path" --content-script "$f1_script" 2>/dev/null; then
    log_info "updated F1 dashboard: $f1_dashboard_path"
  else
    _rc=$?
    log_warn "F1 dashboard helper failed rc=$_rc; continuing"
  fi
else
  log_warn "F1 dashboard helper not found: $f1_dashboard_helper"
fi

populate_block() {
  block_name=$1
  if [ ! -r "$day_plan_script" ]; then
    log_warn "daily plan script not found: $day_plan_script"
    return 0
  fi

  if block_output=$(sh "$day_plan_script" --block "$block_name" 2>/dev/null); then
    printf '%s' "$block_output"
  else
    _rc=$?
    log_warn "daily plan script failed for block='$block_name' rc=$_rc"
    return 0
  fi
}

log_info "preparing time block subnotes: dir=$time_block_subnotes_dir"
if ! mkdir -p "$time_block_subnotes_dir"; then
  log_error "failed to create artifact directory: $time_block_subnotes_dir"
  exit 1
fi

for subnote in "Wake Up" "Morning" "Afternoon" "Evening" "Night"; do
  subnote_path="${time_block_subnotes_dir%/}/${today} - ${subnote}.md"

  block_content=$(populate_block "$subnote" || true)

  if [ -n "${block_content:-}" ]; then
    block_section=$block_content
  else
    block_section='_No entries for this block._'
  fi

  write_atomic_file "$subnote_path" <<EOF_SUBNOTE
# ${subnote} — ${today}

@-- autogenerated: filled from Daily Plan.md by generate-daily-note.sh; do not edit here --

## From Daily Plan
${block_section}

## 🗺️ Navigation

### 🕑 Time Blocks

 [[Periodic Notes/Daily Notes/Subnotes/${today} - Wake Up|Wake Up]] · [[Periodic Notes/Daily Notes/Subnotes/${today} - Morning|Morning]] · [[Periodic Notes/Daily Notes/Subnotes/${today} - Afternoon|Afternoon]] · [[Periodic Notes/Daily Notes/Subnotes/${today} - Evening|Evening]] · [[Periodic Notes/Daily Notes/Subnotes/${today} - Night|Night]]

### 📅 Periodic Notes

[[Periodic Notes/Weekly Notes/${week_tag}|This Week]] · [[Periodic Notes/Monthly Notes/${month_tag}|This Month]] · [[Periodic Notes/Quarterly Notes/${quarter_tag_iso}|This Quarter]] · [[Periodic Notes/Yearly Notes/${year}|This Year]]

### 🔗 Links

[[Weekly Routine]] · [[Consider Johnie]] · [[Daily Note Template]] · [[Daily Plan]] · [[Workout Schedule]]

EOF_SUBNOTE

  # Commit registration (contractual)
  if [ -n "${COMMIT_LIST_FILE:-}" ]; then
    if ! printf '%s\n' "$subnote_path" >>"$COMMIT_LIST_FILE" 2>/dev/null; then
      log_warn "failed to append to COMMIT_LIST_FILE: $COMMIT_LIST_FILE"
    fi
  fi
  log_info "produced subnote: $subnote_path"
done

###############################################################################
# Write main daily note (primary artifact; atomic; contractual)
###############################################################################

primary_parent=${result_ref%/*}
if ! mkdir -p "$primary_parent"; then
  log_error "failed to create artifact directory: $primary_parent"
  exit 1
fi

# Write atomically and clean up temp file on failure/interruption.
tmp="${primary_parent}/${result_ref##*/}.tmp.$$"
cleanup_tmp() {
  [ -n "${tmp:-}" ] && [ -f "$tmp" ] && rm -f "$tmp"
}
trap cleanup_tmp HUP INT TERM 0

if ! generate_main_note >"$tmp"; then
  log_error "failed to write temp artifact: $tmp"
  exit 1
fi
if ! mv "$tmp" "$result_ref"; then
  log_error "failed to finalize artifact (mv): $tmp -> $result_ref"
  exit 1
fi

# Success: disarm cleanup for this temp path.
tmp=""
trap - HUP INT TERM 0

###############################################################################
# Commit registration (contractual)
###############################################################################

if [ -n "${COMMIT_LIST_FILE:-}" ]; then
  if ! printf '%s\n' "$result_ref" >>"$COMMIT_LIST_FILE" 2>/dev/null; then
    log_warn "failed to append to COMMIT_LIST_FILE: $COMMIT_LIST_FILE"
  fi
fi

# Additional artifacts (best-effort): include dashboard if it exists.
if [ -f "$f1_dashboard_path" ]; then
  if [ -n "${COMMIT_LIST_FILE:-}" ]; then
    if ! printf '%s\n' "$f1_dashboard_path" >>"$COMMIT_LIST_FILE" 2>/dev/null; then
      log_warn "failed to append to COMMIT_LIST_FILE: $COMMIT_LIST_FILE"
    fi
  fi
fi

###############################################################################
# Diagnostics
###############################################################################

log_info "Produced artifact: $result_ref"
exit 0
