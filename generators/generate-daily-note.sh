#!/bin/sh
# Generate a daily note markdown file that mirrors the legacy Node implementation.
# Uses helper scripts in ../utils when available to populate dynamic sections.

set -eu

###############################################################################
# Paths, logging, and helpers
###############################################################################

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
utils_dir="$repo_root/utils"
elements_dir="$utils_dir/elements"
finances_dir="$utils_dir/finances"
job_wrap="$repo_root/utils/core/job-wrap.sh"
script_path="$script_dir/$(basename "$0")"

if [ "${JOB_WRAP_ACTIVE:-0}" != "1" ] && [ -x "$job_wrap" ]; then
  JOB_WRAP_ACTIVE=1 exec /bin/sh "$job_wrap" "$script_path" "$@"
fi

log_helper="$repo_root/utils/core/log.sh"
date_helper="$repo_root/utils/core/date-period-helpers.sh"
day_plan_script="$elements_dir/generate-day-plan.sh"
celestial_timings_script="$elements_dir/generate-celestial-timings.sh"
f1_script="$elements_dir/f1-schedule-and-standings.sh"
f1_dashboard_helper="$elements_dir/update-f1-dashboard.sh"
finances_callout_script="$finances_dir/daily-finances-callout.sh"

. "$log_helper"
. "$date_helper"

log_init daily-note

# Ensure common tools are found even under cron (put /usr/local/bin first)
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

###############################################################################
# CLI parsing
###############################################################################

usage() {
  cat <<'EOF_USAGE'
Usage: generate-daily-note.sh [--force] [--dry-run]

Options:
  --force    Overwrite the note if it already exists.
  --dry-run  Write note content to "Daily Note Sample.md" in the repo root without touching the vault.
  --help     Show this message.
EOF_USAGE
}

force=0
dry_run=0

while [ $# -gt 0 ]; do
  case "$1" in
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
      log_err "Unknown option: $1"
      usage >&2
      exit 2
      ;;
  esac
done

###############################################################################
# Output helper
###############################################################################

write_output() {
  dest=$1
  output_target=$dest

  if [ "$dry_run" -eq 1 ] && [ -n "${dry_run_primary_path:-}" ] && [ -n "${dry_run_output_path:-}" ] && [ "$dest" = "$dry_run_primary_path" ]; then
    output_target=$dry_run_output_path
    log_info "Dry run: redirecting output to sample file: $output_target"
    cat >"$output_target"
    return
  fi

  if [ "$dry_run" -eq 1 ]; then
    printf -- '--- DRY RUN: %s ---\n' "$dest"
    cat
    printf -- '--- END DRY RUN: %s ---\n' "$dest"
  else
    cat >"$dest"
  fi
}

ensure_dir() {
  dir=$1
  if [ "$dry_run" -eq 1 ]; then
    log_info "Dry run: would ensure directory exists: $dir"
  else
    mkdir -p "$dir"
  fi
}

###############################################################################
# Vault paths and basic date info
###############################################################################

log_info "Starting daily note generation"

vault_path="${VAULT_PATH:-/home/obsidian/vaults/Main}"
vault_root="${vault_path%/}"
periodic_dir="${vault_root}/Periodic Notes"
daily_note_dir="${periodic_dir%/}/Daily Notes"

log_info "Vault path: $vault_root"
log_info "Daily note directory: $daily_note_dir"

if [ ! -d "$daily_note_dir" ]; then
  log_err "Periodic notes folder does not exist: $daily_note_dir"
  log_err "Edit generate-daily-note.sh to match your vault structure."
  exit 1
fi

today=$(get_today)
current_date_parts=$(get_current_date_parts)
year=${current_date_parts%% *}
month_day=${current_date_parts#* }
month=${month_day%% *}
day=${month_day#* }

week_tag=$(get_current_week_tag)
month_tag=$(get_current_month_tag)
quarter_tag_iso=$(get_quarter_tag_iso)

yesterday=$(get_yesterday)
tomorrow=$(get_tomorrow)

file_path="${daily_note_dir%/}/${today}.md"
dry_run_primary_path=$file_path
dry_run_output_path="${repo_root%/}/Daily Note Sample.md"

log_info "Generating note for date: $today"
log_info "Primary daily note path: $file_path"

###############################################################################
# Finances callout (car loan + credit cards)
###############################################################################

build_finances_callout() {
  if [ ! -r "$finances_callout_script" ]; then
    log_warn "Finances callout script not found: $finances_callout_script"
    return
  fi

  if output=$(sh "$finances_callout_script" "$year" "$month" "$day" 2>/dev/null); then
    printf '%s' "$output"
  else
    status=$?
    log_warn "Finances callout script failed with exit code $status; skipping finances section"
  fi
}

finances_callout=$(build_finances_callout)

###############################################################################
# Time block navigation and periodic links
###############################################################################

time_blocks_nav=$(cat <<EOF_TB
### 🕑 Time Blocks

 [[Periodic Notes/Daily Notes/Subnotes/${today} - Wake Up|Wake Up]] · [[Periodic Notes/Daily Notes/Subnotes/${today} - Morning|Morning]] · [[Periodic Notes/Daily Notes/Subnotes/${today} - Afternoon|Afternoon]] · [[Periodic Notes/Daily Notes/Subnotes/${today} - Evening|Evening]] · [[Periodic Notes/Daily Notes/Subnotes/${today} - Night|Night]]

### 📅 Periodic Notes

[[Periodic Notes/Weekly Notes/${week_tag}|This Week]] · [[Periodic Notes/Monthly Notes/${month_tag}|This Month]] · [[Periodic Notes/Quarterly Notes/${quarter_tag_iso}|This Quarter]] · [[Periodic Notes/Yearly Notes/${year}|This Year]]

### 🔗 Links

[[Weekly Routine]] · [[Consider Johnie]] · [[Daily Note Template]] · [[Daily Plan]] · [[Workout Schedule]]
EOF_TB
)

###############################################################################
# F1 dashboard handling
###############################################################################

f1_dashboard_note="Reference/Dashboards/Formula 1"
f1_dashboard_path="${vault_root%/}/${f1_dashboard_note}.md"

log_info "Formula 1 dashboard note: $f1_dashboard_path"

if [ -r "$f1_dashboard_helper" ]; then
  if [ "$dry_run" -eq 1 ]; then
    sh "$f1_dashboard_helper" --dashboard-path "$f1_dashboard_path" \
      --content-script "$f1_script" --dry-run
  else
    sh "$f1_dashboard_helper" --dashboard-path "$f1_dashboard_path" \
      --content-script "$f1_script"
  fi
else
  log_warn "F1 dashboard helper not found: $f1_dashboard_helper"
fi

###############################################################################
# Overwrite guard for main daily note
###############################################################################

if [ "$dry_run" -eq 1 ]; then
  log_info "Dry run: skipping overwrite guard for $file_path"
elif [ -f "$file_path" ] && [ "$force" -ne 1 ]; then
  log_err "Refusing to overwrite existing file: $file_path"
  printf '     Re-run with --force to overwrite.\n' >&2
  exit 1
fi

###############################################################################
# Time block subnotes
###############################################################################

time_block_subnotes_dir="${daily_note_dir%/}/Subnotes"
ensure_dir "$time_block_subnotes_dir"

populate_block() {
  block_name=$1
  if [ -r "$day_plan_script" ]; then
    sh "$day_plan_script" --block "$block_name" 2>/dev/null || true
  else
    :
  fi
}

log_info "Preparing time block subnotes"
# We'll use positional params solely as commit targets from this point.
set -- "$file_path"
# F1 dashboard may or may not exist in dry-run; we still pass it for parity.
set -- "$@" "$f1_dashboard_path"

for subnote in "Wake Up" "Morning" "Afternoon" "Evening" "Night"; do
  subnote_path="${time_block_subnotes_dir%/}/${today} - ${subnote}.md"
  log_info "Generating subnote for block: $subnote"

  block_content=$(populate_block "$subnote" || true)

  if [ -n "$block_content" ]; then
    block_section=$block_content
  else
    block_section='_No entries for this block._'
  fi

  write_output "$subnote_path" <<EOF_SUBNOTE
# ${subnote} — ${today}

@-- autogenerated: filled from Daily Plan.md by generate-daily-note.sh; do not edit here --

## From Daily Plan
${block_section}

## 🗺️ Navigation

${time_blocks_nav}

EOF_SUBNOTE

  set -- "$@" "$subnote_path"

  if [ "$dry_run" -eq 1 ]; then
    log_info "Dry run: would update subnote: $subnote_path"
  else
    log_info "Subnote updated: $subnote_path"
  fi
done

pagan_timings_text=""

if [ -r "$celestial_timings_script" ]; then
  log_info "Generating celestial timings section"
  if pagan_timings_text=$(sh "$celestial_timings_script"); then
    log_info "Celestial timings section generated"
  else
    status=$?
    log_warn "Celestial timings script failed with exit code $status; using fallback text"
  fi
else
  log_warn "Celestial timings script not found: $celestial_timings_script"
fi

if [ -z "$pagan_timings_text" ]; then
  pagan_timings_text="### 🌌 Celestial Timings
_Celestial timings unavailable._"
fi

###############################################################################
# Daily plan intro (day + focus)
###############################################################################

build_daily_plan_intro() {
  if [ ! -r "$day_plan_script" ]; then
    log_warn "Daily plan script not found, skipping intro"
    return 0
  fi

  log_info "Loading daily plan intro"
  if ! day_plan_output=$(sh "$day_plan_script" 2>/dev/null); then
    log_warn "Daily plan script failed, skipping intro"
    return 0
  fi

  intro_lines=$(printf '%s\n' "$day_plan_output" | awk '
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
  ')

  if [ -n "$intro_lines" ]; then
    log_info "Daily plan intro captured"
    printf '%s\n' "$intro_lines"
  else
    log_warn "Daily plan intro not found in output"
  fi
}

daily_plan_intro=$(build_daily_plan_intro || true)
if [ -n "$daily_plan_intro" ]; then
  daily_plan_intro_section=$(printf '%s\n\n' "$daily_plan_intro")
else
  daily_plan_intro_section=""
fi

###############################################################################
# Callouts / sections
###############################################################################

navigation_callout=$(cat <<EOF_NAVIGATION
> [!note]+ 🗺️ Navigation
$(printf '%s\n' "$time_blocks_nav" | sed 's/^/> /')
EOF_NAVIGATION
)

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

###############################################################################
# Write main daily note
###############################################################################

log_info "Writing daily note content"

write_output "$file_path" <<EOF_NOTE
---
tags:
  - matter/daily-notes
---
<< [[Periodic Notes/Daily Notes/${yesterday}|${yesterday}]] | [[Periodic Notes/Daily Notes/${tomorrow}|${tomorrow}]] >>

${daily_plan_intro_section}${navigation_callout}

${daily_context_callout}

${direction_callout}

${execution_callout}

${finances_callout}

${f1_callout}
EOF_NOTE

if [ "$dry_run" -eq 1 ]; then
  log_info "Dry run: daily note sample written to $dry_run_output_path"
else
  log_info "Daily note created at $file_path"
fi

