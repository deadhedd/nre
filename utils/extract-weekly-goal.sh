#!/bin/sh
# Print the "Weekly Goal" block from the current week's note.

set -e

week_tag=$(date +%G-W%V)
vault_path='/home/obsidian/vaults/Main'
relative="000 - General Knowledge, Information Science, and Computing/005 - Computer Programming, Information, and Security/005.7 - Data/Weekly Notes/$week_tag.md"
file="$vault_path/$relative"

if [ ! -f "$file" ]; then
  echo "❌ Could not find file: $relative"
  exit 1
fi

section=$(awk '/^## 🎯 Weekly Goal/{flag=1; next} /^## / && flag{exit} flag' "$file")
if [ -z "$section" ]; then
  echo "⚠️ Weekly Goal section is empty."
else
  echo "$section"
fi
