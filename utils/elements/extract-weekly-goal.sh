#!/bin/sh
# Print the "Weekly Goal" block from the current week's note.

set -e

week_tag=$(date +%G-W%V)
vault_path="${VAULT_PATH:-/home/obsidian/vaults/Main}"
vault_root="${vault_path%/}"
periodic_dir="${vault_root}/Periodic Notes"
weekly_note_dir="${periodic_dir%/}/Weekly Notes"
relative_path="Periodic Notes/Weekly Notes/${week_tag}.md"
file="${weekly_note_dir%/}/${week_tag}.md"

if [ ! -f "$file" ]; then
  echo "❌ Could not find file: $relative_path"
  exit 1
fi

section=$(awk '/^## 🎯 Weekly Goal/{flag=1; next} /^## / && flag{exit} flag' "$file")
if [ -z "$section" ]; then
  echo "⚠️ Weekly Goal section is empty."
else
  echo "$section"
fi
