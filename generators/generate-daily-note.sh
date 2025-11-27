#!/bin/sh
# Generate a daily note markdown file that mirrors the legacy Node implementation.
# Uses helper scripts in ../utils when available to populate dynamic sections.

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
log_helper="$repo_root/utils/core/log.sh"

. "$log_helper"

usage() {
  cat <<'EOF_USAGE'
Usage: generate-daily-note.sh [--force] [--dry-run]

Options:
  --force    Overwrite the note if it already exists.
  --dry-run  Output the note contents to stdout instead of writing files.
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

write_output() {
  dest=$1
  if [ "$dry_run" -eq 1 ]; then
    printf -- '--- DRY RUN: %s ---\n' "$dest"
    cat
    printf -- '--- END DRY RUN: %s ---\n' "$dest"
  else
    cat >"$dest"
  fi
}

# Ensure common tools are found even under cron (put /usr/local/bin first)
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

log_info "Starting daily note generation"

utils_dir="$repo_root/utils"
elements_dir="$utils_dir/elements"
f1_script="$elements_dir/f1-schedule-and-standings.sh"
commit_helper="$utils_dir/core/commit.sh"
date_helper="$utils_dir/core/date-period-helpers.sh"
day_plan_script="$elements_dir/generate-day-plan.sh"

. "$date_helper"

# Match the legacy default vault path unless overridden and construct
# the periodic notes directory using the same path handling as the
# other non-legacy scripts.
vault_path="${VAULT_PATH:-/home/obsidian/vaults/Main}"
vault_root="${vault_path%/}"
periodic_dir="${vault_root}/Periodic Notes"
daily_note_dir="${periodic_dir%/}/Daily Notes"

log_info "Vault path: $vault_root"
log_info "Daily note directory: $daily_note_dir"

# Ensure the output directory exists
if [ ! -d "$daily_note_dir" ]; then
  log_err "Periodic notes folder does not exist: $daily_note_dir"
  log_err "Edit generate-daily-note.sh to match your vault structure."
  exit 1
fi

# Date helpers
today=$(get_today)
current_date_parts=$(get_current_date_parts)
year=${current_date_parts%% *}
month_day=${current_date_parts#* }
month=${month_day%% *}
day=${month_day#* }
quarter=$(get_current_quarter)
week_tag=$(get_current_week_tag)

# --- Loan payoff countdown (pay on the 20th; payoff 2027-12-20) ---
payoff_y=2027
payoff_m=12
payoff_d=20

# Parse today's Y-M-D into integers that won't trip on leading zeros
ty=$year
tm=$month
td=$day

# Helper: zero-pad to 2 digits
pad2() { [ "$1" -lt 10 ] && printf '0%d' "$1" || printf '%d' "$1"; }

# Months difference ignoring days
months_base=$(( (payoff_y - ty)*12 + (payoff_m - tm) ))

# Round up by one month if we haven't reached the 20th yet this month
if [ "$ty$tm$td" -gt "$payoff_y$(pad2 $payoff_m)$(pad2 $payoff_d)" ]; then
  months_left=0
else
  if [ "$td" -le "$payoff_d" ]; then
    months_left=$(( months_base + 1 ))
  else
    months_left=$(( months_base ))
  fi
  [ "$months_left" -lt 0 ] && months_left=0
fi

# Next payment date (the next 20th on/after today)
np_y=$ty; np_m=$tm; np_d=20
if [ "$td" -gt 20 ]; then
  # advance a month
  if [ "$np_m" -eq 12 ]; then
    np_m=1; np_y=$((np_y+1))
  else
    np_m=$((np_m+1))
  fi
fi

# Payments left: count 20ths from next payment through payoff (inclusive)
if [ "$np_y$(pad2 $np_m)" -gt "$payoff_y$(pad2 $payoff_m)" ]; then
  payments_left=0
else
  payments_left=$(( (payoff_y - np_y)*12 + (payoff_m - np_m) + 1 ))
  [ "$payments_left" -lt 0 ] && payments_left=0
fi

next_payment_fmt="$(printf '%04d-%02d-%02d' "$np_y" "$np_m" 20)"

loan_countdown_text=$(cat <<EOF_LC
## 💰 Loan Payoff Countdown
- **Months left:** ${months_left}
- **Payments left (20ths):** ${payments_left}
- **Next payment:** ${next_payment_fmt}
- **Target payoff:** 2027-12-20
EOF_LC
)


log_info "Generating note for date: $today"

log_info "Preparing time block navigation"

time_blocks_nav=$(cat <<EOF_TB
## ⌚ Time Blocks
- [[Periodic Notes/Daily Notes/${today}|Daily Hub]]
- [[Periodic Notes/Daily Notes/Subnotes/${today} - Wake Up|Wake Up]]
- [[Periodic Notes/Daily Notes/Subnotes/${today} - Morning|Morning]]
- [[Periodic Notes/Daily Notes/Subnotes/${today} - Afternoon|Afternoon]]
- [[Periodic Notes/Daily Notes/Subnotes/${today} - Evening|Evening]]
- [[Periodic Notes/Daily Notes/Subnotes/${today} - Night|Night]]

> [!tip] Power navigation
> - [[Weekly Routine]]
> - [[Stand on Business List]]
> - [[Comms Queue]]
> - [[Device Config Queue]]
> - [[Quick Wins List]]
> - [[Someday / Maybe]]
EOF_TB
)

# Portable yesterday/tomorrow (works on BSD/GNU date)
yesterday=$(get_yesterday)
tomorrow=$(get_tomorrow)

file_path="${daily_note_dir%/}/${today}.md"

f1_dashboard_note="Reference/Dashboards/Formula 1"
f1_dashboard_path="${vault_root%/}/${f1_dashboard_note}.md"
f1_dashboard_embed="![[${f1_dashboard_note}]]"

set -- "$file_path"

log_info "Primary daily note path: $file_path"
log_info "Formula 1 dashboard note: $f1_dashboard_path"

f1_dashboard_dir=$(dirname -- "$f1_dashboard_path")
if [ "$dry_run" -eq 1 ]; then
  log_info "Dry run: would ensure directory exists: $f1_dashboard_dir"
else
  mkdir -p "$f1_dashboard_dir"
fi

if [ ! -f "$f1_dashboard_path" ]; then
  if [ "$dry_run" -eq 1 ]; then
    log_warn "Dry run: Formula 1 dashboard missing; would create placeholder at $f1_dashboard_path"
  else
    log_warn "Formula 1 dashboard missing; creating placeholder at $f1_dashboard_path"
    cat >"$f1_dashboard_path" <<'EOF_F1_DASHBOARD'
# 🏎️ Formula 1
_This dashboard was created automatically. Populate it with race data or widgets for embeds._
EOF_F1_DASHBOARD
    set -- "$@" "$f1_dashboard_path"
  fi
else
  log_info "Formula 1 dashboard present: $f1_dashboard_path"
fi

if [ "$dry_run" -eq 1 ]; then
  log_info "Dry run: skipping Formula 1 dashboard refresh"
elif [ ! -r "$f1_script" ]; then
  log_warn "Formula 1 script not found: $f1_script"
elif ! command -v jq >/dev/null 2>&1; then
  log_warn "Skipping Formula 1 refresh; jq is unavailable"
else
  log_info "Refreshing Formula 1 dashboard content"
  if output=$(sh "$f1_script" 2>/dev/null); then
    printf '%s\n' "$output" | write_output "$f1_dashboard_path"
    log_info "Formula 1 dashboard updated: $f1_dashboard_path"
    set -- "$@" "$f1_dashboard_path"
  else
    status=$?
    log_warn "Formula 1 dashboard refresh failed with exit code $status; leaving existing content"
  fi
fi

# Guard against accidental overwrites unless --force is supplied.
if [ -f "$file_path" ] && [ "$force" -ne 1 ]; then
  log_err "Refusing to overwrite existing file: $file_path"
  printf '     Re-run with --force to overwrite.\n' >&2
  exit 1
fi

# Time block subnote placeholders + content
time_block_subnotes_dir="${daily_note_dir%/}/Subnotes"
if [ "$dry_run" -eq 1 ]; then
  log_info "Dry run: would ensure directory exists: $time_block_subnotes_dir"
else
  mkdir -p "$time_block_subnotes_dir"
fi

populate_block() {
  block_name="$1"   # e.g., "Morning"
  sh "$day_plan_script" --block "$block_name" 2>/dev/null || true
}

for subnote in "Wake Up" "Morning" "Afternoon" "Evening" "Night"; do
  subnote_path="${time_block_subnotes_dir%/}/${today} - ${subnote}.md"

  # Always (over)write content so it stays in sync with the plan:
  log_info "Generating subnote for block: $subnote"
  block_content="$(populate_block "$subnote")"

  if [ -n "$block_content" ]; then
    block_section="$block_content"
  else
    block_section='_No entries for this block._'
  fi

  write_output "$subnote_path" <<EOF_SUBNOTE
# ${subnote} — ${today}

@-- autogenerated: filled from Daily Plan.md by generate-daily-note.sh; do not edit here --

## From Daily Plan
${block_section}

${time_blocks_nav}

EOF_SUBNOTE

  # Add to commit list regardless of new/existing:
  set -- "$@" "$subnote_path"
  if [ "$dry_run" -eq 1 ]; then
    log_info "Dry run: would update subnote: $subnote_path"
  else
    log_info "Subnote updated: $subnote_path"
  fi
done


pagan_header="### Pagan Timings"
moon_text="Moon phase info unavailable."
season_text="Seasonal turning info unavailable."


lunar_cycle_script="$utils_dir/celestial/lunar-cycle.sh"
if [ -r "$lunar_cycle_script" ]; then
  log_info "Gathering lunar cycle data"
  if output=$(sh "$lunar_cycle_script"); then
    log_info "Lunar cycle data retrieved"
    moon_text="$output"
  else
    status=$?
    log_warn "Lunar cycle script failed with exit code $status, using fallback text"
  fi
else
  log_warn "Lunar cycle script not found at $lunar_cycle_script, using fallback text"
fi

seasonal_cycle_script="$utils_dir/celestial/seasonal-cycle.sh"
if [ -r "$seasonal_cycle_script" ]; then
  log_info "Gathering seasonal cycle data"
  if output=$(sh "$seasonal_cycle_script"); then
    log_info "Seasonal cycle data retrieved"
    season_text="$output"
  else
    status=$?
    log_warn "Seasonal cycle script failed with exit code $status, using fallback text"
  fi
else
  log_warn "Seasonal cycle script not found at $seasonal_cycle_script, using fallback text"
fi

pagan_timings_text=$(printf '%s\n%s\n%s\n' "$pagan_header" "$moon_text" "$season_text")

# Daily Plan intro (day + purpose)
daily_plan_intro=""
if [ -r "$day_plan_script" ]; then
  log_info "Loading daily plan intro"
  if day_plan_output=$(sh "$day_plan_script" 2>/dev/null); then
    intro_lines=$(printf '%s\n' "$day_plan_output" | awk '
      /^# Daily Plan - / {in_today=1; next}
      in_today && /^## Preview of Tomorrow:/ {exit}
      in_today {
        if (!day && /^## /) {
          day=$0
          next
        }
        if (!focus && /^### /) {
          focus=$0
        }
      }
      END {
        if (day) print day;
        if (focus) print focus;
      }
    ')
    if [ -n "$intro_lines" ]; then
      log_info "Daily plan intro captured"
      daily_plan_intro="$intro_lines"
    else
      log_warn "Daily plan intro not found in output"
    fi
  else
    log_warn "Daily plan script failed, skipping intro"
  fi
else
  log_warn "Daily plan script not found, skipping intro"
fi

if [ -n "$daily_plan_intro" ]; then
  daily_plan_intro_section=$(printf '%s\n\n' "$daily_plan_intro")
else
  daily_plan_intro_section=""
fi

log_info "Writing daily note content"

# Compose note content with clearer grouping / order.
write_output "$file_path" <<EOF_NOTE
---
tags:
  - matter/daily-notes
---
<< [[Periodic Notes/Daily Notes/${yesterday}|${yesterday}]] | [[Periodic Notes/Daily Notes/${tomorrow}|${tomorrow}]] >>

${daily_plan_intro_section}

## 🧭 Daily Orientation

${time_blocks_nav}

## 🌅 Daily Context

### Sleep
![[Sleep Data/${today} Sleep Summary#Sleep Advice]]

### 🌤️ Yard Work Suitability
<!-- yard-work-check -->

${pagan_timings_text}

## 🎯 Direction & Intent

### [[Yearly theme]] (2025)
The year of standing on business
[[Stand on Business List]]

### [[Season Theme]] (2025 Spring)
Yard work and home repairs

### 🎯 Weekly Goal
![[Periodic Notes/Weekly Notes/${week_tag}#🎯 Weekly Goal]]

## ✅ Execution (Today)

### 🔁 Recurring Today
[[Recurring Tasks]]
\`\`\`tasks
not done
happens today
\`\`\`

### 📌 Focus Buckets

#### Stand on Business
\`\`\`tasks
not done
tags include #stand-on-business
\`\`\`

#### Quick Wins
\`\`\`tasks
not done
tags include #quick-wins
\`\`\`

#### Comms Queue
\`\`\`tasks
not done
tags include #comms-queue
\`\`\`

#### Device Config
\`\`\`tasks
not done
tags include #device-config
\`\`\`

#### Someday/Maybe (Review Only)
\`\`\`tasks
not done
tags include #someday-maybe
\`\`\`

## Finances

${loan_countdown_text}

## 🧭 Periodic Navigation

[[Periodic Notes/Weekly Notes/${week_tag}|This Week]]
[[Periodic Notes/Monthly Notes/${year}-${month}|This Month]]
[[Periodic Notes/Quarterly Notes/${year}-Q${quarter}|This Quarter]]
[[Periodic Notes/Yearly Notes/${year}|This Year]]

## 📊 Dashboards & Reference

${f1_dashboard_embed}

[[Weekly Routine]]
[[Consider Johnie]]
[[Daily Note Template]]
[[Daily Plan]]
[[Workout Schedule]]
EOF_NOTE

if [ "$dry_run" -eq 1 ]; then
  log_info "Dry run: daily note would be created at $file_path"
else
  log_info "Daily note created at $file_path"
fi

if [ "$dry_run" -eq 1 ]; then
  log_info "Dry run: skipping commit helper"
elif [ -x "$commit_helper" ]; then
  log_info "Invoking commit helper"
  "$commit_helper" -c "daily note" "$vault_path" "daily note: $today" "$@"
else
  log_warn "Commit helper not found: $commit_helper"
fi
