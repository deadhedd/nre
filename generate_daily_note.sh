#!/bin/sh
# Generate a daily note markdown file in the Obsidian vault.
# Reimplements generate_daily_note.js using POSIX sh and existing utilities.

set -e

vault_path="/home/chris/automation/obsidian/vaults/Main"
daily_note_dir="$vault_path/000 - General Knowledge, Information Science, and Computing/005 - Computer Programming, Information, and Security/005.7 - Data/Daily Notes"

# Ensure the output directory exists
if [ ! -d "$daily_note_dir" ]; then
  echo "❌ Daily notes folder does not exist: $daily_note_dir" >&2
  exit 1
fi

# Date helpers
today=$(date +%Y-%m-%d)
year=$(date +%Y)
month=$(date +%m)
month_name=$(date +%B)
quarter=$(( (10#$month + 2) / 3 ))
week_number=$(date +%V)

yesterday=$(date -d 'yesterday' +%Y-%m-%d)
tomorrow=$(date -d 'tomorrow' +%Y-%m-%d)

file_path="$daily_note_dir/$today.md"

# Load dynamic sections using helper scripts
day_plan_text=$(./utils/day_plan.sh)
f1_text=$(./utils/f1_schedule.sh)
weekly_goal_text=$(./utils/get_weekly_goal_block.sh)

# Compose note content
cat <<EOF_NOTE > "$file_path"
---
tags:
  - matter/daily-notes
---
<< [[${yesterday}]] | [[${tomorrow}]] >>

${day_plan_text}

## 🌤️ Yard Work Suitability
<!-- yard-work-check -->

---
${f1_text}

---
# Themes and Goals

## [[Yearly theme]] (${year})
The year of standing on business
[[Stand on Business List]]

## [[Season Theme]] (${year} Spring)
Yard work and home repairs

## 🎯 Weekly Goal
${weekly_goal_text}

---

# ☑️ Pending Tasks
### Stand on Business
```tasks
not done
tags include #stand-on-business
```

### Comms Queue
```tasks
not done
tags include #comms-queue
```

### Device Config
```tasks
not done
tags include #device-config
```

### Quick Wins
```tasks
not done
tags include #quick-wins
```

### Someday/Maybe
```tasks
not done
tags include #someday-maybe
```

---

# Periodic Notes

[[${year}-W${week_number}|This Week]]
[[${month_name} ${year}|This Month]]
[[${year}-Q${quarter}|This Quarter]]
[[${year}|This Year]]

---

# Links
[[Weekly Routine]]
[[Consider Johnie]]
[[Daily Note Template]]
[[Daily Plan]]
[[Workout Schedule]]
EOF_NOTE

printf '✅ Daily note created at %s\n' "$file_path"
