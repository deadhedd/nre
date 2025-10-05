#!/bin/sh
# Generate a daily note markdown file that mirrors the legacy Node implementation.
# Uses helper scripts in ./utils when available to populate dynamic sections.

set -eu

# Match the legacy default vault path unless overridden.
vault_path="${VAULT_PATH:-/home/obsidian/vaults/Main}"
daily_note_dir="${vault_path}/Periodic Notes/Daily Notes"

# Ensure the output directory exists
if [ ! -d "$daily_note_dir" ]; then
  echo "❌ Daily notes folder does not exist: $daily_note_dir" >&2
  echo "Edit generate-daily-note.sh to match your vault structure." >&2
  exit 1
fi

# Date helpers
today=$(date +%Y-%m-%d)
year=$(printf '%s' "$today" | cut -d- -f1)
month=$(printf '%s' "$today" | cut -d- -f2)
day=$(printf '%s' "$today" | cut -d- -f3)
quarter=$(( (10#$month + 2) / 3 ))
week_tag=$(date +%G-W%V)

# Compute adjacent dates using only POSIX features so that the script
# remains portable across BSD and GNU date implementations. Adjusting
# the TZ variable by 24 hours effectively shifts the clock a day back
# or forward without relying on non-standard flags.
yesterday=$(TZ=UTC+24 date +%Y-%m-%d)
tomorrow=$(TZ=UTC-24 date +%Y-%m-%d)

file_path="$daily_note_dir/$today.md"

# Optional dynamic sections
day_plan_text="# Daily Plan\n<!-- Daily plan unavailable -->"
if [ -x "./utils/generate-day-plan.sh" ]; then
  if output=$(./utils/generate-day-plan.sh 2>/dev/null); then
    day_plan_text="$output"
  else
    day_plan_text="# Daily Plan\n⚠️ Unable to load day plan"
  fi
fi

f1_text="# 🏎️ Formula 1\n⚠️ Could not load race data."
if [ -x "./utils/f1-schedule-and-standings.sh" ]; then
  if output=$(./utils/f1-schedule-and-standings.sh 2>/dev/null); then
    f1_text="$output"
  fi
fi

weekly_goal_text="⚠️ Weekly Goal section is empty."
if [ -x "./utils/extract-weekly-goal.sh" ]; then
  if output=$(./utils/extract-weekly-goal.sh 2>/dev/null); then
    weekly_goal_text="$output"
  fi
fi

# Compose note content to match the legacy template.
cat <<EOF_NOTE > "$file_path"
---
tags:
  - matter/daily-notes
---
<< [[Periodic Notes/Daily Notes/${yesterday}|${yesterday}]] | [[Periodic Notes/Daily Notes/${tomorrow}|${tomorrow}]] >>

${day_plan_text}

## 🌤️ Yard Work Suitability
<!-- yard-work-check -->

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

printf '✅ Daily note created at %s\n' "$file_path"
