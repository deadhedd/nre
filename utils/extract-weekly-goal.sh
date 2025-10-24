#!/bin/sh
# Print the "Weekly Goal" block from the current week's note.

set -e

week_tag=$(date +%G-W%V)
vault_path='/home/obsidian/vaults/Main'
relative="Periodic Notes/Weekly Notes/$week_tag.md"
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
