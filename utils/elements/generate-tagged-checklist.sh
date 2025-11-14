#!/bin/sh
# Group unchecked tasks by tag from the combined task list.

set -e

vault_path='/home/obsidian/vaults/Main'
file="$vault_path/Inbox/Combined Task List.md"

if [ ! -f "$file" ]; then
  echo '❌ Could not find Inbox/Combined Task List.md'
  exit 1
fi

tmp=$(mktemp)
sed -n '/^- \[ \]/p' "$file" | while IFS= read -r line; do
  tags=$(printf '%s\n' "$line" | grep -o '#[[:alnum:]/-]*')
  [ -z "$tags" ] && continue
  cleaned=$(printf '%s\n' "$line" | sed 's/#[[:alnum:]/-]*//g' | sed 's/[[:space:]]*$//')
  for tag in $tags; do
    printf '%s\t%s\n' "$tag" "$cleaned"
  done
done | sort > "$tmp"

TAB=$(printf '\t')
current=''
while IFS="$TAB" read -r tag item; do
  if [ "$tag" != "$current" ]; then
    [ -n "$current" ] && printf '\n'
    current="$tag"
    heading=$(printf '%s' "$tag" | cut -c2- | tr '-_' ' ')
    formatted=$(printf '%s' "$heading" | awk '{for(i=1;i<=NF;i++){ $i=toupper(substr($i,1,1)) substr($i,2)} print}')
    printf '#### %s List\n' "$formatted"
  fi
  printf '%s\n' "$item"
done < "$tmp"

rm -f "$tmp"
