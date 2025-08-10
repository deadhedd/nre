#!/bin/sh
# Generate a daily note by extracting today's and tomorrow's sections
# from a template markdown file.

vault_base='/home/obsidian/vaults/Main'
relative_path='000 - General Knowledge, Information Science, and Computing/005 - Computer Programming, Information, and Security/005.7 - Data/Templates/Daily Plan.md'
file="$vault_base/$relative_path"

extract_section() {
  day="$1"
  section=$(awk -v pattern="## $day" '
    $0 ~ pattern {found=1; next}
    /^## / && found {exit}
    found {print}
  ' "$file")
  if [ -z "$section" ]; then
    echo "❓ No section found for $day"
  else
    echo "$section"
  fi
}

if [ ! -f "$file" ]; then
  echo "❓ Missing template: $file" >&2
  exit 1
fi

today_name=$(date +%A)
# Use TZ trick instead of GNU's -d flag for portability.
tomorrow_name=$(TZ=UTC-24 date +%A)

echo "# Daily Note - $today_name ($(date +%m/%d/%Y))"
echo
extract_section "$today_name"
echo
echo "## Preview of Tomorrow: $tomorrow_name"
extract_section "$tomorrow_name"
