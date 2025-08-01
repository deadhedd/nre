#!/bin/sh
# Generate a daily note markdown file in the Obsidian vault.
# Example/template for end users to customize.
# Uses optional helper scripts from ./utils if present.

set -e

# Customize this path to point to your Obsidian vault. The VAULT_PATH
# environment variable takes precedence if set.
vault_path="${VAULT_PATH:-/path/to/your/obsidian/vault}"
daily_note_dir="${vault_path}/Daily Notes"

# Ensure the output directory exists
if [ ! -d "$daily_note_dir" ]; then
  echo "❌ Daily notes folder does not exist: $daily_note_dir" >&2
  echo "Edit generate_daily_note.sh to match your vault structure." >&2
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

# Optional dynamic sections
day_plan_text=""
if [ -x "./utils/day_plan.sh" ]; then
  day_plan_text=$(./utils/day_plan.sh)
else
  day_plan_text="# 🗓️ Day Plan\n<!-- Add your plan for the day here -->"
fi

weekly_goal_text=""
if [ -x "./utils/extract-weekly-goal.sh" ]; then
  weekly_goal_text=$(./utils/extract-weekly-goal.sh)
else
  weekly_goal_text="<!-- Weekly goal goes here -->"
fi

# Compose note content. Customize the sections below to suit your workflow.
cat <<EOF_NOTE > "$file_path"
---
tags:
  - daily-note
---

<< [[${yesterday}]] | [[${tomorrow}]] >>

${day_plan_text}

## 🎯 Weekly Goal
${weekly_goal_text}

## ☑️ Tasks
\`\`\`tasks
not done
\`\`\`

## 📓 Notes
<!-- Write your notes here -->

## 📅 Periodic Notes
[[${year}-W${week_number}|This Week]]
[[${month_name} ${year}|This Month]]
[[${year}-Q${quarter}|This Quarter]]
[[${year}|This Year]]

## 🔗 Links
<!-- Example: [[Resources]] -->
EOF_NOTE

printf '✅ Daily note created at %s\n' "$file_path"
