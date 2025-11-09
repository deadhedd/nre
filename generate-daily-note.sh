#!/bin/sh
# Generate a daily note markdown file that mirrors the legacy Node implementation.
# Uses helper scripts in ./utils when available to populate dynamic sections.
#
# Usage: generate-daily-note.sh [--vault <path>] [--outdir <name>] [--date YYYY-MM-DD] [--force]
#
# Options:
#   --vault <path>   Override the vault root (defaults to $VAULT_PATH or /home/obsidian/vaults/Main).
#   --outdir <name>  Subdirectory relative to the vault for the note (defaults to "Periodic Notes/Daily Notes").
#   --date YYYY-MM-DD
#                    Target date for the note (defaults to the current local date).
#   --force          Overwrite existing notes and subnotes instead of skipping them.
#   --help           Show this message.

set -eu

log_info() {
  printf 'ℹ️ %s\n' "$*"
}

log_warn() {
  printf '⚠️ %s\n' "$*"
}

usage() {
  cat <<'EOF_USAGE'
Usage: generate-daily-note.sh [--vault <path>] [--outdir <name>] [--date YYYY-MM-DD] [--force]

Options:
  --vault <path>   Override the vault root. Defaults to $VAULT_PATH or /home/obsidian/vaults/Main.
  --outdir <name>  Subdirectory relative to the vault. Defaults to "Periodic Notes/Daily Notes".
  --date YYYY-MM-DD
                   Target date for the note. Defaults to the current local date.
  --force          Overwrite existing notes and subnotes.
  --help           Show this message.
EOF_USAGE
}

normalize_date() {
  input=$1
  awk '
  function is_leap(year) {
    return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
  }

  function days_in_month(year, month) {
    if (month == 2) {
      return is_leap(year) ? 29 : 28
    }
    if (month == 4 || month == 6 || month == 9 || month == 11) {
      return 30
    }
    return 31
  }

  BEGIN {
    input_date = ARGV[1]
    ARGV[1] = ""

    if (split(input_date, parts, "-") != 3) {
      exit 1
    }

    year = parts[1] + 0
    month = parts[2] + 0
    day = parts[3] + 0

    if (sprintf("%04d-%02d-%02d", year, month, day) != input_date) {
      exit 1
    }

    if (month < 1 || month > 12) {
      exit 1
    }

    limit = days_in_month(year, month)
    if (day < 1 || day > limit) {
      exit 1
    }

    printf "%04d-%02d-%02d", year, month, day
  }
  ' "$input"
}

shift_date() {
  base=$1
  delta=$2
  awk '
  function is_leap(year) {
    return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
  }

  function days_in_month(year, month) {
    if (month == 2) {
      return is_leap(year) ? 29 : 28
    }
    if (month == 4 || month == 6 || month == 9 || month == 11) {
      return 30
    }
    return 31
  }

  function days_before_year(year) {
    y = year - 1
    return y * 365 + int(y / 4) - int(y / 100) + int(y / 400)
  }

  function to_ordinal(date_string,    parts, year, month, day, i, ord) {
    if (split(date_string, parts, "-") != 3) {
      return -1
    }

    year = parts[1] + 0
    month = parts[2] + 0
    day = parts[3] + 0

    if (sprintf("%04d-%02d-%02d", year, month, day) != date_string) {
      return -1
    }

    if (month < 1 || month > 12) {
      return -1
    }

    if (day < 1 || day > days_in_month(year, month)) {
      return -1
    }

    ord = days_before_year(year)
    for (i = 1; i < month; i++) {
      ord += days_in_month(year, i)
    }

    ord += day - 1
    return ord
  }

  function ordinal_to_date(ord,    low, high, mid, year, day_of_year, month, limit) {
    if (ord < 0) {
      exit 1
    }

    low = 1
    high = 1000000

    while (low < high) {
      mid = int((low + high + 1) / 2)
      if (days_before_year(mid) <= ord) {
        low = mid
      } else {
        high = mid - 1
      }
    }

    year = low
    day_of_year = ord - days_before_year(year) + 1

    for (month = 1; month <= 12; month++) {
      limit = days_in_month(year, month)
      if (day_of_year <= limit) {
        printf "%04d-%02d-%02d", year, month, day_of_year
        return
      }
      day_of_year -= limit
    }

    exit 1
  }

  BEGIN {
    date = ARGV[1]
    offset = ARGV[2]
    ARGV[1] = ""
    ARGV[2] = ""

    ord = to_ordinal(date)
    if (ord < 0) {
      exit 1
    }

    target = ord + offset
    ordinal_to_date(target)
  }
  ' "$base" "$delta"
}

format_week_tag() {
  base=$1
  awk '
  function is_leap(year) {
    return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
  }

  function days_in_month(year, month) {
    if (month == 2) {
      return is_leap(year) ? 29 : 28
    }
    if (month == 4 || month == 6 || month == 9 || month == 11) {
      return 30
    }
    return 31
  }

  function floor_val(x, i) {
    i = int(x)
    return (x >= 0 || x == i) ? i : i - 1
  }

  function weekday(year, month, day,    y, m, k, j, h) {
    y = year
    m = month
    if (m <= 2) {
      m += 12
      y -= 1
    }
    k = y % 100
    j = int(y / 100)
    h = (day + floor_val((13 * (m + 1)) / 5) + k + floor_val(k / 4) + floor_val(j / 4) + 5 * j) % 7
    return ((h + 5) % 7) + 1
  }

  function day_of_year(year, month, day,    i, total) {
    total = day
    for (i = 1; i < month; i++) {
      total += days_in_month(year, i)
    }
    return total
  }

  function weeks_in_year(year,    jan1) {
    jan1 = weekday(year, 1, 1)
    if (jan1 == 4 || (jan1 == 3 && is_leap(year))) {
      return 53
    }
    return 52
  }

  function emit_week(date_string,    parts, year, month, day, doy, wday, week, iso_year) {
    if (split(date_string, parts, "-") != 3) {
      return 0
    }

    year = parts[1] + 0
    month = parts[2] + 0
    day = parts[3] + 0

    if (sprintf("%04d-%02d-%02d", year, month, day) != date_string) {
      return 0
    }

    if (month < 1 || month > 12) {
      return 0
    }

    if (day < 1 || day > days_in_month(year, month)) {
      return 0
    }

    doy = day_of_year(year, month, day)
    wday = weekday(year, month, day)
    week = floor_val((doy - wday + 10) / 7)
    iso_year = year

    if (week < 1) {
      iso_year = year - 1
      week = weeks_in_year(iso_year)
    } else if (week > weeks_in_year(year)) {
      iso_year = year + 1
      week = 1
    }

    printf "%04d-W%02d", iso_year, week
    return 1
  }

  BEGIN {
    input_date = ARGV[1]
    ARGV[1] = ""

    if (!emit_week(input_date)) {
      exit 1
    }
  }
  ' "$base"
}

# Ensure common tools are found even under cron (put /usr/local/bin first)
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

log_info "Starting daily note generation"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
commit_helper="$script_dir/utils/commit.sh"

vault_path=${VAULT_PATH:-/home/obsidian/vaults/Main}
outdir="Periodic Notes/Daily Notes"
date_arg=""
force=0

while [ $# -gt 0 ]; do
  case "$1" in
    --vault)
      if [ $# -lt 2 ]; then
        echo "❌ Missing value for --vault" >&2
        usage
        exit 2
      fi
      vault_path=$2
      shift 2
      ;;
    --outdir)
      if [ $# -lt 2 ]; then
        echo "❌ Missing value for --outdir" >&2
        usage
        exit 2
      fi
      outdir=$2
      shift 2
      ;;
    --date)
      if [ $# -lt 2 ]; then
        echo "❌ Missing value for --date" >&2
        usage
        exit 2
      fi
      date_arg=$2
      shift 2
      ;;
    --force)
      force=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "❌ Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

vault_root="${vault_path%/}"
trimmed_outdir=$outdir
while [ "${trimmed_outdir#/}" != "$trimmed_outdir" ]; do
  trimmed_outdir=${trimmed_outdir#/}
done
while [ "${trimmed_outdir%/}" != "$trimmed_outdir" ]; do
  trimmed_outdir=${trimmed_outdir%/}
done

if [ -n "$trimmed_outdir" ]; then
  daily_note_dir="$vault_root/$trimmed_outdir"
else
  daily_note_dir="$vault_root"
fi

if [ -n "$date_arg" ]; then
  case "$date_arg" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
      today=$date_arg
      ;;
    *)
      echo "❌ --date must be in YYYY-MM-DD format" >&2
      exit 2
      ;;
  esac
else
  today=$(date +%Y-%m-%d)
fi

if ! normalized_today=$(normalize_date "$today"); then
  echo "❌ Unable to parse date: $today" >&2
  exit 2
fi

if [ "$normalized_today" != "$today" ]; then
  echo "❌ Invalid date supplied: $today" >&2
  exit 2
fi

year=${today%%-*}
month=${today#*-}
month=${month%%-*}
day=${today##*-}
quarter=$(( (10#$month + 2) / 3 ))
if ! week_tag=$(format_week_tag "$today"); then
  echo "❌ Unable to compute ISO week for: $today" >&2
  exit 2
fi

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


log_info "Vault path: $vault_root"
log_info "Daily note directory: $daily_note_dir"
log_info "Force overwrite: $force"

mkdir -p "$daily_note_dir"

time_block_subnotes_dir="${daily_note_dir%/}/Subnotes"
mkdir -p "$time_block_subnotes_dir"

log_info "Generating note for date: $today"

log_info "Preparing time block navigation"

time_blocks_nav=$(cat <<EOF_TB
## ⌚ Time Blocks
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
if ! yesterday=$(shift_date "$today" -1); then
  echo "❌ Unable to compute yesterday for: $today" >&2
  exit 2
fi
if ! tomorrow=$(shift_date "$today" 1); then
  echo "❌ Unable to compute tomorrow for: $today" >&2
  exit 2
fi

file_path="${daily_note_dir%/}/${today}.md"

set --

log_info "Primary daily note path: $file_path"

populate_block() {
  block_name="$1"   # e.g., "Morning"
  sh "$script_dir/utils/generate-day-plan.sh" --block "$block_name" 2>/dev/null || true
}

for subnote in "Wake Up" "Morning" "Afternoon" "Evening" "Night"; do
  subnote_path="${time_block_subnotes_dir%/}/${today} - ${subnote}.md"

  if [ -f "$subnote_path" ] && [ "$force" -ne 1 ]; then
    log_warn "Subnote exists, skipping (use --force to overwrite): $subnote_path"
    continue
  fi

  log_info "Generating subnote for block: $subnote"
  block_content="$(populate_block "$subnote")"

  {
    printf '# %s — %s\n\n' "$subnote" "$today"
    printf '<!-- autogenerated: filled from Daily Plan.md by generate-daily-note.sh; do not edit here -->\n\n'
    printf '%s\n\n' "$time_blocks_nav"
    printf '## From Daily Plan\n'
    if [ -n "$block_content" ]; then
      printf '%s\n' "$block_content"
    else
      printf '_No entries for this block._\n'
    fi
  } > "$subnote_path"

  set -- "$@" "$subnote_path"
  log_info "Subnote written: $subnote_path"
done

# ----- Defaults as real multiline text (no literal \n) -----
f1_text=$(cat <<'EOF'
# 🏎️ Formula 1
⚠️ Could not load race data.
EOF
)

weekly_goal_text="⚠️ Weekly Goal section is empty."

pagan_header="### Pagan Timings"
moon_text="⚠️ Moon phase info unavailable."
season_text="⚠️ Seasonal turning info unavailable."

# ----- Optional dynamic sections (resolve paths from script_dir; do not require +x) -----
if [ -r "$script_dir/utils/f1-schedule-and-standings.sh" ]; then
  log_info "Fetching Formula 1 data"
  if output=$(sh "$script_dir/utils/f1-schedule-and-standings.sh"); then
    log_info "Formula 1 data retrieved"
    f1_text="$output"
  else
    status=$?
    log_warn "Formula 1 script failed with exit code $status, using fallback text"
  fi
else
  log_warn "Formula 1 script not found at $script_dir/utils/f1-schedule-and-standings.sh, using fallback text"
fi

if [ -r "$script_dir/utils/extract-weekly-goal.sh" ]; then
  log_info "Extracting weekly goal"
  if output=$(sh "$script_dir/utils/extract-weekly-goal.sh"); then
    log_info "Weekly goal extracted"
    weekly_goal_text="$output"
  else
    status=$?
    log_warn "Weekly goal script failed with exit code $status, using fallback text"
  fi
else
  log_warn "Weekly goal script not found at $script_dir/utils/extract-weekly-goal.sh, using fallback text"
fi

pagan_moon_script="$script_dir/utils/pagan-moon.sh"
if [ -r "$pagan_moon_script" ]; then
  log_info "Gathering pagan moon data"
  if output=$(sh "$pagan_moon_script"); then
    log_info "Pagan moon data retrieved"
    moon_text="$output"
  else
    status=$?
    log_warn "Pagan moon script failed with exit code $status, using fallback text"
  fi
else
  log_warn "Pagan moon script not found at $pagan_moon_script, using fallback text"
fi

pagan_seasons_script="$script_dir/utils/pagan-seasons.sh"
if [ -r "$pagan_seasons_script" ]; then
  log_info "Gathering pagan season data"
  if output=$(sh "$pagan_seasons_script"); then
    log_info "Pagan season data retrieved"
    season_text="$output"
  else
    status=$?
    log_warn "Pagan seasons script failed with exit code $status, using fallback text"
  fi
else
  log_warn "Pagan seasons script not found at $pagan_seasons_script, using fallback text"
fi

pagan_timings_text=$(printf '%s\n%s\n%s\n' "$pagan_header" "$moon_text" "$season_text")

# Daily Plan intro (day + purpose)
daily_plan_intro=""
day_plan_script="$script_dir/utils/generate-day-plan.sh"
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

if [ -f "$file_path" ] && [ "$force" -ne 1 ]; then
  log_warn "Daily note already exists, skipping (use --force to overwrite): $file_path"
else
  log_info "Writing daily note content"

  # Compose note content to match the legacy template.
  cat <<EOF_NOTE > "$file_path"
---
tags:
  - matter/daily-notes
---
<< [[Periodic Notes/Daily Notes/${yesterday}|${yesterday}]] | [[Periodic Notes/Daily Notes/${tomorrow}|${tomorrow}]] >>

${daily_plan_intro_section}${pagan_timings_text}

${time_blocks_nav}

## 🌤️ Yard Work Suitability
<!-- yard-work-check -->

---

# Finances

${loan_countdown_text}

---
${f1_text}

---
# Themes and Goals

## [[Yearly theme]] (2025)
The year of standing on business
[[Stand on Business List]]

## [[Season Theme]] (2025 Spring)
Yard work and home repairs

## 🎯 Weekly Goal
${weekly_goal_text}

---

# ☑️ Pending Tasks
### Stand on Business
\`\`\`tasks
not done
tags include #stand-on-business
\`\`\`

### Comms Queue
\`\`\`tasks
not done
tags include #comms-queue
\`\`\`

### Device Config
\`\`\`tasks
not done
tags include #device-config
\`\`\`

### Quick Wins
\`\`\`tasks
not done
tags include #quick-wins
\`\`\`

### Someday/Maybe
\`\`\`tasks
not done
tags include #someday-maybe
\`\`\`

---

# Periodic Notes

[[Periodic Notes/Weekly Notes/${week_tag}|This Week]]
[[Periodic Notes/Monthly Notes/${year}-${month}|This Month]]
[[Periodic Notes/Quarterly Notes/${year}-Q${quarter}|This Quarter]]
[[Periodic Notes/Yearly Notes/${year}|This Year]]

---

# Links
[[Weekly Routine]]
[[Consider Johnie]]
[[Daily Note Template]]
[[Daily Plan]]
[[Workout Schedule]]
EOF_NOTE
  log_info "Daily note written: $file_path"
  printf '✅ Daily note created at %s\n' "$file_path"
  set -- "$@" "$file_path"
fi

if [ -x "$commit_helper" ]; then
  if [ $# -gt 0 ]; then
    log_info "Invoking commit helper"
    "$commit_helper" -c "daily note" "$vault_path" "daily note: $today" "$@"
  else
    log_info "No files written; skipping commit helper"
  fi
else
  log_warn "Commit helper not found: $commit_helper"
  printf '⚠️ commit helper not found: %s\n' "$commit_helper" >&2
fi

