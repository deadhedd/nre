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

lib_dir=$repo_root/lib
periods_lib=$lib_dir/periods.sh
datetime_lib=$lib_dir/datetime.sh
day_plan_script="$elements_dir/generate-day-plan.sh"
celestial_timings_script="$elements_dir/generate-celestial-timings.sh"
f1_script="$elements_dir/f1-schedule-and-standings.sh"
f1_dashboard_helper="$elements_dir/update-f1-dashboard.sh"
finances_callout_script="$finances_dir/daily-finances-callout.sh"

# Periods (days / weeks / months / quarters)
if [ ! -r "$periods_lib" ]; then
  printf 'ERR  %s\n' "periods lib not found/readable: $periods_lib" >&2
  exit 127
fi
# shellcheck source=/dev/null
. "$periods_lib" || {
  printf 'ERR  %s\n' "failed to source periods lib: $periods_lib" >&2
  exit 127
}

# Datetime (local-time only)
if [ ! -r "$datetime_lib" ]; then
  printf 'ERR  %s\n' "datetime lib not found/readable: $datetime_lib" >&2
  exit 127
fi
# shellcheck source=/dev/null
. "$datetime_lib" || {
  printf 'ERR  %s\n' "failed to source datetime lib: $datetime_lib" >&2
  exit 127
}

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
      printf 'ERR  %s\n' "Unknown option: $1" >&2
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
    printf 'INFO %s\n' "Dry run: redirecting output to sample file: $output_target"
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
    printf 'INFO %s\n' "Dry run: would ensure directory exists: $dir"
  else
    mkdir -p "$dir"
  fi
}

###############################################################################
# Vault paths and basic date info
###############################################################################

printf 'INFO %s\n' "Starting daily note generation"

vault_path="${VAULT_PATH:-/home/obsidian/vaults/Main}"
vault_root="${vault_path%/}"
periodic_dir="${vault_root}/Periodic Notes"
daily_note_dir="${periodic_dir%/}/Daily Notes"

printf 'INFO %s\n' "Vault path: $vault_root"
printf 'INFO %s\n' "Daily note directory: $daily_note_dir"

if [ ! -d "$daily_note_dir" ]; then
  printf 'ERR  %s\n' "Periodic notes folder does not exist: $daily_note_dir" >&2
  printf 'ERR  %s\n' "Edit generate-daily-note.sh to match your vault structure." >&2
  exit 1
fi

today=$(pr_today)
current_date_parts=$(pr_date_parts)
year=${current_date_parts%% *}
month_day=${current_date_parts#* }
month=${month_day%% *}
day=${month_day#* }

week_tag=$(pr_week_tag_current)
month_tag=$(pr_month_tag_current)
quarter_tag_iso=$(pr_quarter_tag_iso)

yesterday=$(pr_yesterday)
tomorrow=$(pr_tomorrow)

file_path="${daily_note_dir%/}/${today}.md"
dry_run_primary_path=$file_path
dry_run_output_path="${repo_root%/}/Daily Note Sample.md"

printf 'INFO %s\n' "Generating note for date: $today"
printf 'INFO %s\n' "Primary daily note path: $file_path"

###############################################################################
# Finances callout (car loan + credit cards)
###############################################################################

build_finances_callout() {
  if [ ! -r "$finances_callout_script" ]; then
    printf 'WARN %s\n' "Finances callout script not found: $finances_callout_script" >&2
    return
  fi

  if output=$(sh "$finances_callout_script" "$year" "$month" "$day" 2>/dev/null); then
    printf '%s' "$output"
  else
    status=$?
    printf 'WARN %s\n' "Finances callout script failed with exit code $status; skipping finances section" >&2
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

printf 'INFO %s\n' "Formula 1 dashboard note: $f1_dashboard_path"

if [ -r "$f1_dashboard_helper" ]; then
  if [ "$dry_run" -eq 1 ]; then
    sh "$f1_dashboard_helper" --dashboard-path "$f1_dashboard_path" \
      --content-script "$f1_script" --dry-run
  else
    sh "$f1_dashboard_helper" --dashboard-path "$f1_dashboard_path" \
      --content-script "$f1_script"
  fi
else
  printf 'WARN %s\n' "F1 dashboard helper not found: $f1_dashboard_helper" >&2
fi

###############################################################################
# Overwrite guard for main daily note
###############################################################################

if [ "$dry_run" -eq 1 ]; then
  printf 'INFO %s\n' "Dry run: skipping overwrite guard for $file_path"
elif [ -f "$file_path" ] && [ "$force" -ne 1 ]; then
  printf 'ERR  %s\n' "Refusing to overwrite existing file: $file_path" >&2
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
  # Warn instead of exiting so daily note generation continues even if the plan is incomplete.
  if [ ! -r "$day_plan_script" ]; then
    printf 'WARN %s\n' "Daily plan script not found: $day_plan_script" >&2
    return 0
  fi

  if block_output=$(sh "$day_plan_script" --block "$block_name" 2>/dev/null); then
    printf '%s' "$block_output"
  else
    status=$?
    printf 'WARN %s\n' "Daily plan script failed for block '$block_name' with exit code $status" >&2
    return 0
  fi
}

printf 'INFO %s\n' "Preparing time block subnotes"
# We'll use positional params solely as commit targets from this point.
set -- "$file_path"
# F1 dashboard may or may not exist in dry-run; we still pass it for parity.
set -- "$@" "$f1_dashboard_path"

for subnote in "Wake Up" "Morning" "Afternoon" "Evening" "Night"; do
  subnote_path="${time_block_subnotes_dir%/}/${today} - ${subnote}.md"
  printf 'INFO %s\n' "Generating subnote for block: $subnote"

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
    printf 'INFO %s\n' "Dry run: would update subnote: $subnote_path"
  else
    printf 'INFO %s\n' "Subnote updated: $subnote_path"
  fi
done

pagan_timings_text=""

if [ -r "$celestial_timings_script" ]; then
  printf 'INFO %s\n' "Generating celestial timings section"
  if pagan_timings_text=$(sh "$celestial_timings_script"); then
    printf 'INFO %s\n' "Celestial timings section generated"
  else
    status=$?
    printf 'WARN %s\n' "Celestial timings script failed with exit code $status; using fallback text" >&2
  fi
else
  printf 'WARN %s\n' "Celestial timings script not found: $celestial_timings_script" >&2
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
    printf 'WARN %s\n' "Daily plan script not found, skipping intro" >&2
    return 0
  fi

  printf 'INFO %s\n' "Loading daily plan intro"
  if ! day_plan_output=$(sh "$day_plan_script" 2>/dev/null); then
    printf 'WARN %s\n' "Daily plan script failed, skipping intro" >&2
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
    printf 'INFO %s\n' "Daily plan intro captured"
    printf '%s\n' "$intro_lines"
  else
    printf 'WARN %s\n' "Daily plan intro not found in output" >&2
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

printf 'INFO %s\n' "Writing daily note content"

write_output "$file_path" <<EOF_NOTE
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

if [ "$dry_run" -eq 1 ]; then
  printf 'INFO %s\n' "Dry run: daily note sample written to $dry_run_output_path"
else
  printf 'INFO %s\n' "Daily note created at $file_path"
fi
